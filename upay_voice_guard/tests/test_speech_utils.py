from app.speech_utils import phone_to_speech, speakable

def test_phone_to_speech():
    assert phone_to_speech("01755555555") == "শূন্য এক সাত, পাঁচ পাঁচ পাঁচ পাঁচ, পাঁচ পাঁচ পাঁচ পাঁচ"
    assert phone_to_speech("8801307339929") == "শূন্য এক তিন, শূন্য সাত তিন তিন, নয় নয় দুই নয়"
    assert phone_to_speech("+8801911111111") == "শূন্য এক নয়, এক এক এক এক, এক এক এক এক"
    assert phone_to_speech("123") == "এক দুই তিন"

def test_speakable():
    # Number conversion + phone translation
    assert speakable("My number is 01755555555") == "My number is শূন্য এক সাত, পাঁচ পাঁচ পাঁচ পাঁচ, পাঁচ পাঁচ পাঁচ পাঁচ"
    
    # Normal numbers to Bangla numbers
    assert speakable("আপনার ব্যালেন্স 25000 টাকা") == "আপনার ব্যালেন্স ২৫০০০ টাকা"
    
    # TK / BDT replacement
    assert speakable("Total 500 TK and 200 BDT") == "Total ৫০০ টাকা and ২০০ টাকা"
    
    # Complex mix
    assert speakable("01755555555 নম্বরে 500 TK Cash Out") == "শূন্য এক সাত, পাঁচ পাঁচ পাঁচ পাঁচ, পাঁচ পাঁচ পাঁচ পাঁচ নম্বরে ৫০০ টাকা Cash Out"
