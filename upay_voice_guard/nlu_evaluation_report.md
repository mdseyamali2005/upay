# NLU Evaluation Report

**Date**: 2026-10-07 09:31
**Dataset**: 85 samples across 17 categories
**Intents tested**: cash_out, balance, spending, send_money, bye, faq, unknown

## 1. Overall Accuracy

| Method | Correct | Total | Accuracy |
|--------|---------|-------|----------|
| Rule-based | 70 | 85 | **82.4%** |
| Gemini LLM | 8 | 85 | **9.4%** |
| Combined (prod) | 84 | 85 | **98.8%** |

## 2. Per-Intent Metrics (Combined / Production)

| Intent | Precision | Recall | F1 | Support |
|--------|-----------|--------|----|---------|
| cash_out | 0.95 | 1.00 | 0.97 | 18 |
| balance | 1.00 | 0.94 | 0.97 | 17 |
| spending | 1.00 | 1.00 | 1.00 | 12 |
| send_money | 1.00 | 1.00 | 1.00 | 7 |
| bye | 1.00 | 1.00 | 1.00 | 10 |
| faq | 1.00 | 1.00 | 1.00 | 13 |
| unknown | 1.00 | 1.00 | 1.00 | 8 |

## 3. Accuracy by Category

| Category | Rule-based | Gemini | Combined |
|----------|------------|--------|----------|
| ambiguous | 3/3 | 3/3 | 3/3 |
| asr_error | 6/6 | 0/6 | 6/6 |
| banglish | 15/18 | 0/18 | 18/18 |
| code_switch | 2/2 | 0/2 | 2/2 |
| compound | 0/2 | 0/2 | 1/2 |
| dialect_barishal | 1/1 | 0/1 | 1/1 |
| dialect_chittagong | 4/4 | 0/4 | 4/4 |
| dialect_common | 3/3 | 0/3 | 3/3 |
| dialect_noakhali | 1/1 | 0/1 | 1/1 |
| dialect_rangpur | 1/1 | 0/1 | 1/1 |
| dialect_sylheti | 3/3 | 0/3 | 3/3 |
| misspelling | 2/2 | 0/2 | 2/2 |
| out_of_domain | 3/3 | 3/3 | 3/3 |
| standard_bangla | 24/30 | 0/30 | 30/30 |
| tricky | 0/2 | 0/2 | 2/2 |
| unsupported_valid | 1/2 | 1/2 | 2/2 |
| vague | 1/2 | 1/2 | 2/2 |

## 4. Confusion Matrix (Combined)

| Expected \ Predicted | cash_out | balance | spending | send_money | bye | faq | unknown |
|---|---|---|---|---|---|---|---|
| **cash_out** | 18 | 0 | 0 | 0 | 0 | 0 | 0 |
| **balance** | 1 | 16 | 0 | 0 | 0 | 0 | 0 |
| **spending** | 0 | 0 | 12 | 0 | 0 | 0 | 0 |
| **send_money** | 0 | 0 | 0 | 7 | 0 | 0 | 0 |
| **bye** | 0 | 0 | 0 | 0 | 10 | 0 | 0 |
| **faq** | 0 | 0 | 0 | 0 | 0 | 13 | 0 |
| **unknown** | 0 | 0 | 0 | 0 | 0 | 0 | 8 |

## 5. Rule-based vs Gemini Comparison

| Intent | Rule P/R/F1 | Gemini P/R/F1 | Combined P/R/F1 | Winner |
|--------|-------------|---------------|-----------------|--------|
| cash_out | 0.72/1.00/0.84 | 0.00/0.00/0.00 | 0.95/1.00/0.97 | Combined |
| balance | 1.00/0.88/0.94 | 0.00/0.00/0.00 | 1.00/0.94/0.97 | Combined |
| spending | 1.00/1.00/1.00 | 0.00/0.00/0.00 | 1.00/1.00/1.00 | Combined |
| send_money | 0.88/1.00/0.93 | 0.00/0.00/0.00 | 1.00/1.00/1.00 | Combined |
| bye | 1.00/1.00/1.00 | 0.00/0.00/0.00 | 1.00/1.00/1.00 | Combined |
| faq | 0.00/0.00/0.00 | 0.00/0.00/0.00 | 1.00/1.00/1.00 | Combined |
| unknown | 0.53/1.00/0.70 | 0.09/1.00/0.17 | 1.00/1.00/1.00 | Combined |

## 6. Error Analysis (Combined)

| # | Text | Expected | Predicted | Category | Note |
|---|------|----------|-----------|----------|------|
| 70 | ব্যালেন্স দেখে তারপর ক্যাশ আউট করব | balance | cash_out | compound | First action is balance |
