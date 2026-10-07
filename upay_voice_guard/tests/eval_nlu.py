"""NLU Evaluation Harness — compares rule-based NLU vs Gemini LLM NLU.

Produces:
  - Per-intent accuracy, precision, recall, F1
  - Confusion matrix
  - Overall accuracy breakdown by category (standard, banglish, dialect, ASR error)
  - Side-by-side rule vs Gemini comparison (T2)

Run:
    cd p:\\1upay\\upay_voice_guard
    python -m tests.eval_nlu
"""
import json
import os
import sys
import time
import logging
from collections import defaultdict
from pathlib import Path

# Add parent dir to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.nlu import parse_intent as _rule_parse_intent  # noqa: E402

log = logging.getLogger(__name__)

DATASET_PATH = Path(__file__).parent / "intent_dataset.json"
REPORT_PATH = Path(__file__).parent.parent / "nlu_evaluation_report.md"

ALL_INTENTS = ["cash_out", "balance", "spending", "send_money", "bye", "faq", "unknown"]


def rule_only_parse(text: str) -> dict:
    """Rule-based NLU only (bypass LLM fallback)."""
    import unicodedata, re
    from app.nlu import _CASH, _BAL, _SPEND, _SEND, _BYE, _tokens

    t = unicodedata.normalize("NFC", text.lower())
    if any(w in t for w in _SPEND):
        month = "this" if ("এই মাস" in t or "this month" in t) else "last"
        return {"intent": "spending", "month": month}
    if any(w in t for w in _CASH):
        return {"intent": "cash_out"}
    if any(w in t for w in _BAL):
        return {"intent": "balance"}
    if any(w in t for w in _SEND):
        return {"intent": "send_money"}
    if set(_tokens(t)) & _BYE:
        return {"intent": "bye"}
    return {"intent": "unknown"}


def gemini_only_parse(text: str) -> dict:
    """Gemini LLM NLU only (no rule fallback)."""
    try:
        from app.llm_nlu import llm_parse_intent
        result = llm_parse_intent(text)
        if result and "intent" in result:
            return result
    except Exception:
        pass
    return {"intent": "unknown"}


def combined_parse(text: str) -> dict:
    """Combined: Gemini first, then rule fallback (production behavior)."""
    return _rule_parse_intent(text)


def evaluate(dataset, parser_fn, parser_name="parser"):
    """Run evaluation and return metrics dict."""
    results = {
        "total": 0,
        "correct": 0,
        "per_intent": {i: {"tp": 0, "fp": 0, "fn": 0} for i in ALL_INTENTS},
        "per_category": defaultdict(lambda: {"total": 0, "correct": 0}),
        "confusion": defaultdict(lambda: defaultdict(int)),
        "errors": [],
    }

    for sample in dataset:
        text = sample["text"]
        expected = sample["expected_intent"]
        category = sample.get("category", "unknown")

        try:
            predicted = parser_fn(text)
            pred_intent = predicted.get("intent", "unknown")
        except Exception as e:
            pred_intent = "unknown"
            log.warning("Parser error on '%s': %s", text, e)

        results["total"] += 1
        results["per_category"][category]["total"] += 1
        results["confusion"][expected][pred_intent] += 1

        correct = pred_intent == expected
        if correct:
            results["correct"] += 1
            results["per_category"][category]["correct"] += 1
            results["per_intent"][expected]["tp"] += 1
        else:
            results["per_intent"][expected]["fn"] += 1
            results["per_intent"][pred_intent]["fp"] += 1
            results["errors"].append({
                "id": sample.get("id"),
                "text": text,
                "expected": expected,
                "predicted": pred_intent,
                "category": category,
                "note": sample.get("note", ""),
            })

    return results


def compute_metrics(results):
    """Compute precision, recall, F1 per intent from TP/FP/FN."""
    metrics = {}
    for intent in ALL_INTENTS:
        tp = results["per_intent"][intent]["tp"]
        fp = results["per_intent"][intent]["fp"]
        fn = results["per_intent"][intent]["fn"]
        precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
        f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0
        metrics[intent] = {
            "precision": precision,
            "recall": recall,
            "f1": f1,
            "tp": tp, "fp": fp, "fn": fn,
            "support": tp + fn,
        }
    return metrics


def format_report(rule_results, gemini_results, combined_results, dataset):
    """Generate a Markdown report comparing all three NLU methods."""
    rule_metrics = compute_metrics(rule_results)
    gemini_metrics = compute_metrics(gemini_results)
    combined_metrics = compute_metrics(combined_results)

    lines = []
    lines.append("# NLU Evaluation Report")
    lines.append(f"\n**Date**: {time.strftime('%Y-%m-%d %H:%M')}")
    lines.append(f"**Dataset**: {len(dataset)} samples across {len(set(s['category'] for s in dataset))} categories")
    lines.append(f"**Intents tested**: {', '.join(ALL_INTENTS)}")

    # ── Overall Accuracy ──
    lines.append("\n## 1. Overall Accuracy\n")
    lines.append("| Method | Correct | Total | Accuracy |")
    lines.append("|--------|---------|-------|----------|")
    for name, r in [("Rule-based", rule_results), ("Gemini LLM", gemini_results), ("Combined (prod)", combined_results)]:
        acc = r["correct"] / r["total"] * 100 if r["total"] else 0
        lines.append(f"| {name} | {r['correct']} | {r['total']} | **{acc:.1f}%** |")

    # ── Per-Intent Metrics (Combined) ──
    lines.append("\n## 2. Per-Intent Metrics (Combined / Production)\n")
    lines.append("| Intent | Precision | Recall | F1 | Support |")
    lines.append("|--------|-----------|--------|----|---------|")
    for intent in ALL_INTENTS:
        m = combined_metrics[intent]
        if m["support"] > 0:
            lines.append(f"| {intent} | {m['precision']:.2f} | {m['recall']:.2f} | {m['f1']:.2f} | {m['support']} |")

    # ── Per-Category Accuracy ──
    lines.append("\n## 3. Accuracy by Category\n")
    lines.append("| Category | Rule-based | Gemini | Combined |")
    lines.append("|----------|------------|--------|----------|")
    all_cats = sorted(set(
        list(rule_results["per_category"].keys()) +
        list(gemini_results["per_category"].keys()) +
        list(combined_results["per_category"].keys())
    ))
    for cat in all_cats:
        rule_c = rule_results["per_category"].get(cat, {"correct": 0, "total": 0})
        gem_c = gemini_results["per_category"].get(cat, {"correct": 0, "total": 0})
        comb_c = combined_results["per_category"].get(cat, {"correct": 0, "total": 0})
        r_pct = f"{rule_c['correct']}/{rule_c['total']}" if rule_c['total'] else "—"
        g_pct = f"{gem_c['correct']}/{gem_c['total']}" if gem_c['total'] else "—"
        c_pct = f"{comb_c['correct']}/{comb_c['total']}" if comb_c['total'] else "—"
        lines.append(f"| {cat} | {r_pct} | {g_pct} | {c_pct} |")

    # ── Confusion Matrix (Combined) ──
    lines.append("\n## 4. Confusion Matrix (Combined)\n")
    present = [i for i in ALL_INTENTS if any(combined_results["confusion"][i].values()) or
               any(combined_results["confusion"][j][i] for j in ALL_INTENTS)]
    lines.append("| Expected \\ Predicted | " + " | ".join(present) + " |")
    lines.append("|" + "---|" * (len(present) + 1))
    for exp in present:
        row = [str(combined_results["confusion"][exp].get(p, 0)) for p in present]
        lines.append(f"| **{exp}** | " + " | ".join(row) + " |")

    # ── Rule vs Gemini comparison (T2 requirement) ──
    lines.append("\n## 5. Rule-based vs Gemini Comparison\n")
    lines.append("| Intent | Rule P/R/F1 | Gemini P/R/F1 | Combined P/R/F1 | Winner |")
    lines.append("|--------|-------------|---------------|-----------------|--------|")
    for intent in ALL_INTENTS:
        rm, gm, cm = rule_metrics[intent], gemini_metrics[intent], combined_metrics[intent]
        if rm["support"] == 0 and gm["support"] == 0:
            continue
        winner = "Combined" if cm["f1"] >= max(rm["f1"], gm["f1"]) else ("Gemini" if gm["f1"] > rm["f1"] else "Rule")
        lines.append(
            f"| {intent} | {rm['precision']:.2f}/{rm['recall']:.2f}/{rm['f1']:.2f} | "
            f"{gm['precision']:.2f}/{gm['recall']:.2f}/{gm['f1']:.2f} | "
            f"{cm['precision']:.2f}/{cm['recall']:.2f}/{cm['f1']:.2f} | {winner} |"
        )

    # ── Error Analysis ──
    lines.append("\n## 6. Error Analysis (Combined)\n")
    if combined_results["errors"]:
        lines.append("| # | Text | Expected | Predicted | Category | Note |")
        lines.append("|---|------|----------|-----------|----------|------|")
        for e in combined_results["errors"][:30]:
            lines.append(f"| {e['id']} | {e['text']} | {e['expected']} | {e['predicted']} | {e['category']} | {e.get('note', '')} |")
    else:
        lines.append("✅ No errors — all samples classified correctly!")

    return "\n".join(lines) + "\n"


def main():
    print("=" * 60)
    print("NLU Evaluation Harness")
    print("=" * 60)

    # Load dataset
    with open(DATASET_PATH, encoding="utf-8") as f:
        dataset = json.load(f)
    print(f"\nLoaded {len(dataset)} samples from {DATASET_PATH.name}")

    # ── Evaluate Rule-based ──
    print("\n[1/3] Evaluating rule-based NLU...")
    rule_results = evaluate(dataset, rule_only_parse, "rule-based")
    r_acc = rule_results["correct"] / rule_results["total"] * 100
    print(f"      Rule-based accuracy: {rule_results['correct']}/{rule_results['total']} ({r_acc:.1f}%)")

    # ── Evaluate Gemini ──
    print("\n[2/3] Evaluating Gemini LLM NLU...")
    has_gemini = bool(os.environ.get("GEMINI_API_KEY"))
    if has_gemini:
        gemini_results = evaluate(dataset, gemini_only_parse, "gemini")
        g_acc = gemini_results["correct"] / gemini_results["total"] * 100
        print(f"      Gemini accuracy: {gemini_results['correct']}/{gemini_results['total']} ({g_acc:.1f}%)")
    else:
        print("      [!] GEMINI_API_KEY not set -- Gemini results will be all 'unknown'")
        gemini_results = evaluate(dataset, gemini_only_parse, "gemini")

    # ── Evaluate Combined ──
    print("\n[3/3] Evaluating combined (production) NLU...")
    combined_results = evaluate(dataset, combined_parse, "combined")
    c_acc = combined_results["correct"] / combined_results["total"] * 100
    print(f"      Combined accuracy: {combined_results['correct']}/{combined_results['total']} ({c_acc:.1f}%)")

    # ── Generate report ──
    report = format_report(rule_results, gemini_results, combined_results, dataset)
    with open(REPORT_PATH, "w", encoding="utf-8") as f:
        f.write(report)
    print(f"\n[OK] Report written to {REPORT_PATH}")

    # ── Print summary ──
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"  Rule-based:  {r_acc:.1f}%")
    if has_gemini:
        print(f"  Gemini LLM:  {g_acc:.1f}%")
    print(f"  Combined:    {c_acc:.1f}%")
    print(f"  Errors:      {len(combined_results['errors'])}")
    print()


if __name__ == "__main__":
    main()
