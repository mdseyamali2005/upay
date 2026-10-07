"""Text-first call simulator. Type what you'd press/say.
 [keypad] = digits only     [voice] = a sentence
 !limit 3000  -> change the limit like the website would      !reset -> fresh demo DB"""
from app import db
from app.flow import Session

db.init_db()
s = Session()
r = s.start()
while True:
    print(f"\n🤖 {r['say']}")
    if r["end"]:
        break
    tag = "keypad" if r["expect"] == "keypad" else "voice"
    text = input(f"[{tag}] > ").strip()
    if text.startswith("!limit"):
        db.set_limit(db.DEMO_USER_ID, int(text.split()[1]))
        print("   (limit updated from website)")
        continue
    if text == "!reset":
        db.init_db(reset=True); s = Session(); r = s.start(); continue
    r = s.handle("keypad" if tag == "keypad" else "speech", text)
