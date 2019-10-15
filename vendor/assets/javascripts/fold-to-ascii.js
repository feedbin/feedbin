/**
 * fold-to-ascii.js
 * https://github.com/mplatt/fold-to-ascii-js
 *
 * This is a JavaScript port of the Apache Lucene ASCII Folding Filter.
 *
 * The Apache Lucene ASCII Folding Filter is licensed to the Apache Software
 * Foundation (ASF) under one or more contributor license agreements. See the
 * NOTICE file distributed with this work for additional information regarding
 * copyright ownership. The ASF licenses this file to You under the Apache
 * License, Version 2.0 (the "License"); you may not use this file except in
 * compliance with the License. You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 * License for the specific language governing permissions and limitations under
 * the License.
 *
 * This port uses an example from the Mozilla Developer Network published prior
 * to August 20, 2010
 *
 * fixedCharCodeAt is licencesed under the MIT License (MIT)
 *
 * Copyright (c) 2013 Mozilla Developer Network and individual contributors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

(function() {
	/*
	 * True if unmapped non-ASCII characters should be replaced by the
	 * default-string.
	 * False if unmapped characters should remain in the output string.
	 */
	var replaceUnmapped = true;

	/*
	 * Default string to replace unmapped characters with
	 */
	var defaultString = "_";

	String.prototype.foldToASCII = function() {
		return foldToASCII(this);
	};

	foldToASCII = function(inStr) {
		if (inStr === null) {
			return "";
		}

		/*
		 * The array of characters or character combinations to output
		 */
		var outStr = "";

		for (var i = 0; i < inStr.length; i++) {
			var charCode = fixedCharCodeAt(inStr, i);

			/*
			 * Skip low surrogates
			 */
			if (charCode) {
				if (charCode < 128) {
					/*
					 * Character within the ASCII range.
					 * Copy it to the output string.
					 */
					outStr += String.fromCharCode(charCode);
				} else {
					/*
					 * Character outside of the ASCII range.
					 * Look for a replacement
					 */
					outStr += replaceChar(charCode);
				}
			}
		}

		return outStr;
	};

	var fixedCharCodeAt = function(str, idx) {
		/*
		 * ex. fixedCharCodeAt ('\uD800\uDC00', 0); // 65536
		 * ex. fixedCharCodeAt ('\uD800\uDC00', 1); // 65536
		 */
		idx = idx || 0;
		var code = str.charCodeAt(idx);
		var hi, low;

		/*
		 * High surrogate (could change last hex to 0xDB7F to treat high
		 * private surrogates as single characters)
		 */
		if (0xD800 <= code && code <= 0xDBFF) {
			hi = code;
			low = str.charCodeAt(idx + 1);
			if (isNaN(low)) {
				throw 'High surrogate not followed by low surrogate in fixedCharCodeAt()';
			}
			return ((hi - 0xD800) * 0x400) + (low - 0xDC00) + 0x10000;
		}
		if (0xDC00 <= code && code <= 0xDFFF) {
			/*
			 * Low surrogate: We return false to allow loops to skip this
			 * iteration since should have already handled high surrogate above
			 * in the previous iteration
			 */
			return false;
			/*
			 * hi = str.charCodeAt(idx-1); low = code; return ((hi - 0xD800) *
			 * 0x400) + (low - 0xDC00) + 0x10000;
			 */
		}
		return code;
	};

	/*
	 * Replaces a character with an ASCII compliant character or
	 * character-combination.
	 */
	var replaceChar = function(charCode) {
		var outString = "";

		switch (charCode) {
			case 0xC0: // À	[LATIN CAPITAL LETTER A WITH GRAVE]
			case 0xC1: // Á	[LATIN CAPITAL LETTER A WITH ACUTE]
			case 0xC2: // Â	[LATIN CAPITAL LETTER A WITH CIRCUMFLEX]
			case 0xC3: // Ã	[LATIN CAPITAL LETTER A WITH TILDE]
			case 0xC4: // Ä	[LATIN CAPITAL LETTER A WITH DIAERESIS]
			case 0xC5: // Å	[LATIN CAPITAL LETTER A WITH RING ABOVE]
			case 0x100: // Ā	[LATIN CAPITAL LETTER A WITH MACRON]
			case 0x102: // Ă	[LATIN CAPITAL LETTER A WITH BREVE]
			case 0x104: // Ą	[LATIN CAPITAL LETTER A WITH OGONEK]
			case 0x18F: // Ə	http://en.wikipedia.org/wiki/Schwa	[LATIN CAPITAL LETTER SCHWA]
			case 0x1CD: // Ǎ	[LATIN CAPITAL LETTER A WITH CARON]
			case 0x1DE: // Ǟ	[LATIN CAPITAL LETTER A WITH DIAERESIS AND MACRON]
			case 0x1E0: // Ǡ	[LATIN CAPITAL LETTER A WITH DOT ABOVE AND MACRON]
			case 0x1FA: // Ǻ	[LATIN CAPITAL LETTER A WITH RING ABOVE AND ACUTE]
			case 0x200: // Ȁ	[LATIN CAPITAL LETTER A WITH DOUBLE GRAVE]
			case 0x202: // Ȃ	[LATIN CAPITAL LETTER A WITH INVERTED BREVE]
			case 0x226: // Ȧ	[LATIN CAPITAL LETTER A WITH DOT ABOVE]
			case 0x23A: // Ⱥ	[LATIN CAPITAL LETTER A WITH STROKE]
			case 0x1D00: // ᴀ	[LATIN LETTER SMALL CAPITAL A]
			case 0x1E00: // Ḁ	[LATIN CAPITAL LETTER A WITH RING BELOW]
			case 0x1EA0: // Ạ	[LATIN CAPITAL LETTER A WITH DOT BELOW]
			case 0x1EA2: // Ả	[LATIN CAPITAL LETTER A WITH HOOK ABOVE]
			case 0x1EA4: // Ấ	[LATIN CAPITAL LETTER A WITH CIRCUMFLEX AND ACUTE]
			case 0x1EA6: // Ầ	[LATIN CAPITAL LETTER A WITH CIRCUMFLEX AND GRAVE]
			case 0x1EA8: // Ẩ	[LATIN CAPITAL LETTER A WITH CIRCUMFLEX AND HOOK ABOVE]
			case 0x1EAA: // Ẫ	[LATIN CAPITAL LETTER A WITH CIRCUMFLEX AND TILDE]
			case 0x1EAC: // Ậ	[LATIN CAPITAL LETTER A WITH CIRCUMFLEX AND DOT BELOW]
			case 0x1EAE: // Ắ	[LATIN CAPITAL LETTER A WITH BREVE AND ACUTE]
			case 0x1EB0: // Ằ	[LATIN CAPITAL LETTER A WITH BREVE AND GRAVE]
			case 0x1EB2: // Ẳ	[LATIN CAPITAL LETTER A WITH BREVE AND HOOK ABOVE]
			case 0x1EB4: // Ẵ	[LATIN CAPITAL LETTER A WITH BREVE AND TILDE]
			case 0x1EB6: // Ặ	[LATIN CAPITAL LETTER A WITH BREVE AND DOT BELOW]
			case 0x24B6: // Ⓐ	[CIRCLED LATIN CAPITAL LETTER A]
			case 0xFF21: // Ａ	[FULLWIDTH LATIN CAPITAL LETTER A]
				outString += "A";
				break;
			case 0xE0: // à	[LATIN SMALL LETTER A WITH GRAVE]
			case 0xE1: // á	[LATIN SMALL LETTER A WITH ACUTE]
			case 0xE2: // â	[LATIN SMALL LETTER A WITH CIRCUMFLEX]
			case 0xE3: // ã	[LATIN SMALL LETTER A WITH TILDE]
			case 0xE4: // ä	[LATIN SMALL LETTER A WITH DIAERESIS]
			case 0xE5: // å	[LATIN SMALL LETTER A WITH RING ABOVE]
			case 0x101: // ā	[LATIN SMALL LETTER A WITH MACRON]
			case 0x103: // ă	[LATIN SMALL LETTER A WITH BREVE]
			case 0x105: // ą	[LATIN SMALL LETTER A WITH OGONEK]
			case 0x1CE: // ǎ	[LATIN SMALL LETTER A WITH CARON]
			case 0x1DF: // ǟ	[LATIN SMALL LETTER A WITH DIAERESIS AND MACRON]
			case 0x1E1: // ǡ	[LATIN SMALL LETTER A WITH DOT ABOVE AND MACRON]
			case 0x1FB: // ǻ	[LATIN SMALL LETTER A WITH RING ABOVE AND ACUTE]
			case 0x201: // ȁ	[LATIN SMALL LETTER A WITH DOUBLE GRAVE]
			case 0x203: // ȃ	[LATIN SMALL LETTER A WITH INVERTED BREVE]
			case 0x227: // ȧ	[LATIN SMALL LETTER A WITH DOT ABOVE]
			case 0x250: // ɐ	[LATIN SMALL LETTER TURNED A]
			case 0x259: // ə	[LATIN SMALL LETTER SCHWA]
			case 0x25A: // ɚ	[LATIN SMALL LETTER SCHWA WITH HOOK]
			case 0x1D8F: // ᶏ	[LATIN SMALL LETTER A WITH RETROFLEX HOOK]
			case 0x1D95: // ᶕ	[LATIN SMALL LETTER SCHWA WITH RETROFLEX HOOK]
			case 0x1E01: // ạ	[LATIN SMALL LETTER A WITH RING BELOW]
			case 0x1E9A: // ả	[LATIN SMALL LETTER A WITH RIGHT HALF RING]
			case 0x1EA1: // ạ	[LATIN SMALL LETTER A WITH DOT BELOW]
			case 0x1EA3: // ả	[LATIN SMALL LETTER A WITH HOOK ABOVE]
			case 0x1EA5: // ấ	[LATIN SMALL LETTER A WITH CIRCUMFLEX AND ACUTE]
			case 0x1EA7: // ầ	[LATIN SMALL LETTER A WITH CIRCUMFLEX AND GRAVE]
			case 0x1EA9: // ẩ	[LATIN SMALL LETTER A WITH CIRCUMFLEX AND HOOK ABOVE]
			case 0x1EAB: // ẫ	[LATIN SMALL LETTER A WITH CIRCUMFLEX AND TILDE]
			case 0x1EAD: // ậ	[LATIN SMALL LETTER A WITH CIRCUMFLEX AND DOT BELOW]
			case 0x1EAF: // ắ	[LATIN SMALL LETTER A WITH BREVE AND ACUTE]
			case 0x1EB1: // ằ	[LATIN SMALL LETTER A WITH BREVE AND GRAVE]
			case 0x1EB3: // ẳ	[LATIN SMALL LETTER A WITH BREVE AND HOOK ABOVE]
			case 0x1EB5: // ẵ	[LATIN SMALL LETTER A WITH BREVE AND TILDE]
			case 0x1EB7: // ặ	[LATIN SMALL LETTER A WITH BREVE AND DOT BELOW]
			case 0x2090: // ₐ	[LATIN SUBSCRIPT SMALL LETTER A]
			case 0x2094: // ₔ	[LATIN SUBSCRIPT SMALL LETTER SCHWA]
			case 0x24D0: // ⓐ	[CIRCLED LATIN SMALL LETTER A]
			case 0x2C65: // ⱥ	[LATIN SMALL LETTER A WITH STROKE]
			case 0x2C6F: // Ɐ	[LATIN CAPITAL LETTER TURNED A]
			case 0xFF41: // ａ	[FULLWIDTH LATIN SMALL LETTER A]
				outString += "a";
				break;
			case 0xA732: // Ꜳ	[LATIN CAPITAL LETTER AA]
				outString += "A";
				outString += "A";
				break;
			case 0xC6: // Æ	[LATIN CAPITAL LETTER AE]
			case 0x1E2: // Ǣ	[LATIN CAPITAL LETTER AE WITH MACRON]
			case 0x1FC: // Ǽ	[LATIN CAPITAL LETTER AE WITH ACUTE]
			case 0x1D01: // ᴁ	[LATIN LETTER SMALL CAPITAL AE]
				outString += "A";
				outString += "E";
				break;
			case 0xA734: // Ꜵ	[LATIN CAPITAL LETTER AO]
				outString += "A";
				outString += "O";
				break;
			case 0xA736: // Ꜷ	[LATIN CAPITAL LETTER AU]
				outString += "A";
				outString += "U";
				break;
			case 0xA738: // Ꜹ	[LATIN CAPITAL LETTER AV]
			case 0xA73A: // Ꜻ	[LATIN CAPITAL LETTER AV WITH HORIZONTAL BAR]
				outString += "A";
				outString += "V";
				break;
			case 0xA73C: // Ꜽ	[LATIN CAPITAL LETTER AY]
				outString += "A";
				outString += "Y";
				break;
			case 0x249C: // ⒜	[PARENTHESIZED LATIN SMALL LETTER A]
				outString += "(";
				outString += "a";
				outString += ")";
				break;
			case 0xA733: // ꜳ	[LATIN SMALL LETTER AA]
				outString += "a";
				outString += "a";
				break;
			case 0xE6: // æ	[LATIN SMALL LETTER AE]
			case 0x1E3: // ǣ	[LATIN SMALL LETTER AE WITH MACRON]
			case 0x1FD: // ǽ	[LATIN SMALL LETTER AE WITH ACUTE]
			case 0x1D02: // ᴂ	[LATIN SMALL LETTER TURNED AE]
				outString += "a";
				outString += "e";
				break;
			case 0xA735: // ꜵ	[LATIN SMALL LETTER AO]
				outString += "a";
				outString += "o";
				break;
			case 0xA737: // ꜷ	[LATIN SMALL LETTER AU]
				outString += "a";
				outString += "u";
				break;
			case 0xA739: // ꜹ	[LATIN SMALL LETTER AV]
			case 0xA73B: // ꜻ	[LATIN SMALL LETTER AV WITH HORIZONTAL BAR]
				outString += "a";
				outString += "v";
				break;
			case 0xA73D: // ꜽ	[LATIN SMALL LETTER AY]
				outString += "a";
				outString += "y";
				break;
			case 0x181: // Ɓ	[LATIN CAPITAL LETTER B WITH HOOK]
			case 0x182: // Ƃ	[LATIN CAPITAL LETTER B WITH TOPBAR]
			case 0x243: // Ƀ	[LATIN CAPITAL LETTER B WITH STROKE]
			case 0x299: // ʙ	[LATIN LETTER SMALL CAPITAL B]
			case 0x1D03: // ᴃ	[LATIN LETTER SMALL CAPITAL BARRED B]
			case 0x1E02: // Ḃ	[LATIN CAPITAL LETTER B WITH DOT ABOVE]
			case 0x1E04: // Ḅ	[LATIN CAPITAL LETTER B WITH DOT BELOW]
			case 0x1E06: // Ḇ	[LATIN CAPITAL LETTER B WITH LINE BELOW]
			case 0x24B7: // Ⓑ	[CIRCLED LATIN CAPITAL LETTER B]
			case 0xFF22: // Ｂ	[FULLWIDTH LATIN CAPITAL LETTER B]
				outString += "B";
				break;
			case 0x180: // ƀ	[LATIN SMALL LETTER B WITH STROKE]
			case 0x183: // ƃ	[LATIN SMALL LETTER B WITH TOPBAR]
			case 0x253: // ɓ	[LATIN SMALL LETTER B WITH HOOK]
			case 0x1D6C: // ᵬ	[LATIN SMALL LETTER B WITH MIDDLE TILDE]
			case 0x1D80: // ᶀ	[LATIN SMALL LETTER B WITH PALATAL HOOK]
			case 0x1E03: // ḃ	[LATIN SMALL LETTER B WITH DOT ABOVE]
			case 0x1E05: // ḅ	[LATIN SMALL LETTER B WITH DOT BELOW]
			case 0x1E07: // ḇ	[LATIN SMALL LETTER B WITH LINE BELOW]
			case 0x24D1: // ⓑ	[CIRCLED LATIN SMALL LETTER B]
			case 0xFF42: // ｂ	[FULLWIDTH LATIN SMALL LETTER B]
				outString += "b";
				break;
			case 0x249D: // ⒝	[PARENTHESIZED LATIN SMALL LETTER B]
				outString += "(";
				outString += "b";
				outString += ")";
				break;
			case 0xC7: // Ç	[LATIN CAPITAL LETTER C WITH CEDILLA]
			case 0x106: // Ć	[LATIN CAPITAL LETTER C WITH ACUTE]
			case 0x108: // Ĉ	[LATIN CAPITAL LETTER C WITH CIRCUMFLEX]
			case 0x10A: // Ċ	[LATIN CAPITAL LETTER C WITH DOT ABOVE]
			case 0x10C: // Č	[LATIN CAPITAL LETTER C WITH CARON]
			case 0x187: // Ƈ	[LATIN CAPITAL LETTER C WITH HOOK]
			case 0x23B: // Ȼ	[LATIN CAPITAL LETTER C WITH STROKE]
			case 0x297: // ʗ	[LATIN LETTER STRETCHED C]
			case 0x1D04: // ᴄ	[LATIN LETTER SMALL CAPITAL C]
			case 0x1E08: // Ḉ	[LATIN CAPITAL LETTER C WITH CEDILLA AND ACUTE]
			case 0x24B8: // Ⓒ	[CIRCLED LATIN CAPITAL LETTER C]
			case 0xFF23: // Ｃ	[FULLWIDTH LATIN CAPITAL LETTER C]
				outString += "C";
				break;
			case 0xE7: // ç	[LATIN SMALL LETTER C WITH CEDILLA]
			case 0x107: // ć	[LATIN SMALL LETTER C WITH ACUTE]
			case 0x109: // ĉ	[LATIN SMALL LETTER C WITH CIRCUMFLEX]
			case 0x10B: // ċ	[LATIN SMALL LETTER C WITH DOT ABOVE]
			case 0x10D: // č	[LATIN SMALL LETTER C WITH CARON]
			case 0x188: // ƈ	[LATIN SMALL LETTER C WITH HOOK]
			case 0x23C: // ȼ	[LATIN SMALL LETTER C WITH STROKE]
			case 0x255: // ɕ	[LATIN SMALL LETTER C WITH CURL]
			case 0x1E09: // ḉ	[LATIN SMALL LETTER C WITH CEDILLA AND ACUTE]
			case 0x2184: // ↄ	[LATIN SMALL LETTER REVERSED C]
			case 0x24D2: // ⓒ	[CIRCLED LATIN SMALL LETTER C]
			case 0xA73E: // Ꜿ	[LATIN CAPITAL LETTER REVERSED C WITH DOT]
			case 0xA73F: // ꜿ	[LATIN SMALL LETTER REVERSED C WITH DOT]
			case 0xFF43: // ｃ	[FULLWIDTH LATIN SMALL LETTER C]
				outString += "c";
				break;
			case 0x249E: // ⒞	[PARENTHESIZED LATIN SMALL LETTER C]
				outString += "(";
				outString += "c";
				outString += ")";
				break;
			case 0xD0: // Ð	[LATIN CAPITAL LETTER ETH]
			case 0x10E: // Ď	[LATIN CAPITAL LETTER D WITH CARON]
			case 0x110: // Đ	[LATIN CAPITAL LETTER D WITH STROKE]
			case 0x189: // Ɖ	[LATIN CAPITAL LETTER AFRICAN D]
			case 0x18A: // Ɗ	[LATIN CAPITAL LETTER D WITH HOOK]
			case 0x18B: // Ƌ	[LATIN CAPITAL LETTER D WITH TOPBAR]
			case 0x1D05: // ᴅ	[LATIN LETTER SMALL CAPITAL D]
			case 0x1D06: // ᴆ	[LATIN LETTER SMALL CAPITAL ETH]
			case 0x1E0A: // Ḋ	[LATIN CAPITAL LETTER D WITH DOT ABOVE]
			case 0x1E0C: // Ḍ	[LATIN CAPITAL LETTER D WITH DOT BELOW]
			case 0x1E0E: // Ḏ	[LATIN CAPITAL LETTER D WITH LINE BELOW]
			case 0x1E10: // Ḑ	[LATIN CAPITAL LETTER D WITH CEDILLA]
			case 0x1E12: // Ḓ	[LATIN CAPITAL LETTER D WITH CIRCUMFLEX BELOW]
			case 0x24B9: // Ⓓ	[CIRCLED LATIN CAPITAL LETTER D]
			case 0xA779: // Ꝺ	[LATIN CAPITAL LETTER INSULAR D]
			case 0xFF24: // Ｄ	[FULLWIDTH LATIN CAPITAL LETTER D]
				outString += "D";
				break;
			case 0xF0: // ð	[LATIN SMALL LETTER ETH]
			case 0x10F: // ď	[LATIN SMALL LETTER D WITH CARON]
			case 0x111: // đ	[LATIN SMALL LETTER D WITH STROKE]
			case 0x18C: // ƌ	[LATIN SMALL LETTER D WITH TOPBAR]
			case 0x221: // ȡ	[LATIN SMALL LETTER D WITH CURL]
			case 0x256: // ɖ	[LATIN SMALL LETTER D WITH TAIL]
			case 0x257: // ɗ	[LATIN SMALL LETTER D WITH HOOK]
			case 0x1D6D: // ᵭ	[LATIN SMALL LETTER D WITH MIDDLE TILDE]
			case 0x1D81: // ᶁ	[LATIN SMALL LETTER D WITH PALATAL HOOK]
			case 0x1D91: // ᶑ	[LATIN SMALL LETTER D WITH HOOK AND TAIL]
			case 0x1E0B: // ḋ	[LATIN SMALL LETTER D WITH DOT ABOVE]
			case 0x1E0D: // ḍ	[LATIN SMALL LETTER D WITH DOT BELOW]
			case 0x1E0F: // ḏ	[LATIN SMALL LETTER D WITH LINE BELOW]
			case 0x1E11: // ḑ	[LATIN SMALL LETTER D WITH CEDILLA]
			case 0x1E13: // ḓ	[LATIN SMALL LETTER D WITH CIRCUMFLEX BELOW]
			case 0x24D3: // ⓓ	[CIRCLED LATIN SMALL LETTER D]
			case 0xA77A: // ꝺ	[LATIN SMALL LETTER INSULAR D]
			case 0xFF44: // ｄ	[FULLWIDTH LATIN SMALL LETTER D]
				outString += "d";
				break;
			case 0x1C4: // Ǆ	[LATIN CAPITAL LETTER DZ WITH CARON]
			case 0x1F1: // Ǳ	[LATIN CAPITAL LETTER DZ]
				outString += "D";
				outString += "Z";
				break;
			case 0x1C5: // ǅ	[LATIN CAPITAL LETTER D WITH SMALL LETTER Z WITH CARON]
			case 0x1F2: // ǲ	[LATIN CAPITAL LETTER D WITH SMALL LETTER Z]
				outString += "D";
				outString += "z";
				break;
			case 0x249F: // ⒟	[PARENTHESIZED LATIN SMALL LETTER D]
				outString += "(";
				outString += "d";
				outString += ")";
				break;
			case 0x238: // ȸ	[LATIN SMALL LETTER DB DIGRAPH]
				outString += "d";
				outString += "b";
				break;
			case 0x1C6: // ǆ	[LATIN SMALL LETTER DZ WITH CARON]
			case 0x1F3: // ǳ	[LATIN SMALL LETTER DZ]
			case 0x2A3: // ʣ	[LATIN SMALL LETTER DZ DIGRAPH]
			case 0x2A5: // ʥ	[LATIN SMALL LETTER DZ DIGRAPH WITH CURL]
				outString += "d";
				outString += "z";
				break;
			case 0xC8: // È	[LATIN CAPITAL LETTER E WITH GRAVE]
			case 0xC9: // É	[LATIN CAPITAL LETTER E WITH ACUTE]
			case 0xCA: // Ê	[LATIN CAPITAL LETTER E WITH CIRCUMFLEX]
			case 0xCB: // Ë	[LATIN CAPITAL LETTER E WITH DIAERESIS]
			case 0x112: // Ē	[LATIN CAPITAL LETTER E WITH MACRON]
			case 0x114: // Ĕ	[LATIN CAPITAL LETTER E WITH BREVE]
			case 0x116: // Ė	[LATIN CAPITAL LETTER E WITH DOT ABOVE]
			case 0x118: // Ę	[LATIN CAPITAL LETTER E WITH OGONEK]
			case 0x11A: // Ě	[LATIN CAPITAL LETTER E WITH CARON]
			case 0x18E: // Ǝ	[LATIN CAPITAL LETTER REVERSED E]
			case 0x190: // Ɛ	[LATIN CAPITAL LETTER OPEN E]
			case 0x204: // Ȅ	[LATIN CAPITAL LETTER E WITH DOUBLE GRAVE]
			case 0x206: // Ȇ	[LATIN CAPITAL LETTER E WITH INVERTED BREVE]
			case 0x228: // Ȩ	[LATIN CAPITAL LETTER E WITH CEDILLA]
			case 0x246: // Ɇ	[LATIN CAPITAL LETTER E WITH STROKE]
			case 0x1D07: // ᴇ	[LATIN LETTER SMALL CAPITAL E]
			case 0x1E14: // Ḕ	[LATIN CAPITAL LETTER E WITH MACRON AND GRAVE]
			case 0x1E16: // Ḗ	[LATIN CAPITAL LETTER E WITH MACRON AND ACUTE]
			case 0x1E18: // Ḙ	[LATIN CAPITAL LETTER E WITH CIRCUMFLEX BELOW]
			case 0x1E1A: // Ḛ	[LATIN CAPITAL LETTER E WITH TILDE BELOW]
			case 0x1E1C: // Ḝ	[LATIN CAPITAL LETTER E WITH CEDILLA AND BREVE]
			case 0x1EB8: // Ẹ	[LATIN CAPITAL LETTER E WITH DOT BELOW]
			case 0x1EBA: // Ẻ	[LATIN CAPITAL LETTER E WITH HOOK ABOVE]
			case 0x1EBC: // Ẽ	[LATIN CAPITAL LETTER E WITH TILDE]
			case 0x1EBE: // Ế	[LATIN CAPITAL LETTER E WITH CIRCUMFLEX AND ACUTE]
			case 0x1EC0: // Ề	[LATIN CAPITAL LETTER E WITH CIRCUMFLEX AND GRAVE]
			case 0x1EC2: // Ể	[LATIN CAPITAL LETTER E WITH CIRCUMFLEX AND HOOK ABOVE]
			case 0x1EC4: // Ễ	[LATIN CAPITAL LETTER E WITH CIRCUMFLEX AND TILDE]
			case 0x1EC6: // Ệ	[LATIN CAPITAL LETTER E WITH CIRCUMFLEX AND DOT BELOW]
			case 0x24BA: // Ⓔ	[CIRCLED LATIN CAPITAL LETTER E]
			case 0x2C7B: // ⱻ	[LATIN LETTER SMALL CAPITAL TURNED E]
			case 0xFF25: // Ｅ	[FULLWIDTH LATIN CAPITAL LETTER E]
				outString += "E";
				break;
			case 0xE8: // è	[LATIN SMALL LETTER E WITH GRAVE]
			case 0xE9: // é	[LATIN SMALL LETTER E WITH ACUTE]
			case 0xEA: // ê	[LATIN SMALL LETTER E WITH CIRCUMFLEX]
			case 0xEB: // ë	[LATIN SMALL LETTER E WITH DIAERESIS]
			case 0x113: // ē	[LATIN SMALL LETTER E WITH MACRON]
			case 0x115: // ĕ	[LATIN SMALL LETTER E WITH BREVE]
			case 0x117: // ė	[LATIN SMALL LETTER E WITH DOT ABOVE]
			case 0x119: // ę	[LATIN SMALL LETTER E WITH OGONEK]
			case 0x11B: // ě	[LATIN SMALL LETTER E WITH CARON]
			case 0x1DD: // ǝ	[LATIN SMALL LETTER TURNED E]
			case 0x205: // ȅ	[LATIN SMALL LETTER E WITH DOUBLE GRAVE]
			case 0x207: // ȇ	[LATIN SMALL LETTER E WITH INVERTED BREVE]
			case 0x229: // ȩ	[LATIN SMALL LETTER E WITH CEDILLA]
			case 0x247: // ɇ	[LATIN SMALL LETTER E WITH STROKE]
			case 0x258: // ɘ	[LATIN SMALL LETTER REVERSED E]
			case 0x25B: // ɛ	[LATIN SMALL LETTER OPEN E]
			case 0x25C: // ɜ	[LATIN SMALL LETTER REVERSED OPEN E]
			case 0x25D: // ɝ	[LATIN SMALL LETTER REVERSED OPEN E WITH HOOK]
			case 0x25E: // ɞ	[LATIN SMALL LETTER CLOSED REVERSED OPEN E]
			case 0x29A: // ʚ	[LATIN SMALL LETTER CLOSED OPEN E]
			case 0x1D08: // ᴈ	[LATIN SMALL LETTER TURNED OPEN E]
			case 0x1D92: // ᶒ	[LATIN SMALL LETTER E WITH RETROFLEX HOOK]
			case 0x1D93: // ᶓ	[LATIN SMALL LETTER OPEN E WITH RETROFLEX HOOK]
			case 0x1D94: // ᶔ	[LATIN SMALL LETTER REVERSED OPEN E WITH RETROFLEX HOOK]
			case 0x1E15: // ḕ	[LATIN SMALL LETTER E WITH MACRON AND GRAVE]
			case 0x1E17: // ḗ	[LATIN SMALL LETTER E WITH MACRON AND ACUTE]
			case 0x1E19: // ḙ	[LATIN SMALL LETTER E WITH CIRCUMFLEX BELOW]
			case 0x1E1B: // ḛ	[LATIN SMALL LETTER E WITH TILDE BELOW]
			case 0x1E1D: // ḝ	[LATIN SMALL LETTER E WITH CEDILLA AND BREVE]
			case 0x1EB9: // ẹ	[LATIN SMALL LETTER E WITH DOT BELOW]
			case 0x1EBB: // ẻ	[LATIN SMALL LETTER E WITH HOOK ABOVE]
			case 0x1EBD: // ẽ	[LATIN SMALL LETTER E WITH TILDE]
			case 0x1EBF: // ế	[LATIN SMALL LETTER E WITH CIRCUMFLEX AND ACUTE]
			case 0x1EC1: // ề	[LATIN SMALL LETTER E WITH CIRCUMFLEX AND GRAVE]
			case 0x1EC3: // ể	[LATIN SMALL LETTER E WITH CIRCUMFLEX AND HOOK ABOVE]
			case 0x1EC5: // ễ	[LATIN SMALL LETTER E WITH CIRCUMFLEX AND TILDE]
			case 0x1EC7: // ệ	[LATIN SMALL LETTER E WITH CIRCUMFLEX AND DOT BELOW]
			case 0x2091: // ₑ	[LATIN SUBSCRIPT SMALL LETTER E]
			case 0x24D4: // ⓔ	[CIRCLED LATIN SMALL LETTER E]
			case 0x2C78: // ⱸ	[LATIN SMALL LETTER E WITH NOTCH]
			case 0xFF45: // ｅ	[FULLWIDTH LATIN SMALL LETTER E]
				outString += "e";
				break;
			case 0x24A0: // ⒠	[PARENTHESIZED LATIN SMALL LETTER E]
				outString += "(";
				outString += "e";
				outString += ")";
				break;
			case 0x191: // Ƒ	[LATIN CAPITAL LETTER F WITH HOOK]
			case 0x1E1E: // Ḟ	[LATIN CAPITAL LETTER F WITH DOT ABOVE]
			case 0x24BB: // Ⓕ	[CIRCLED LATIN CAPITAL LETTER F]
			case 0xA730: // ꜰ	[LATIN LETTER SMALL CAPITAL F]
			case 0xA77B: // Ꝼ	[LATIN CAPITAL LETTER INSULAR F]
			case 0xA7FB: // ꟻ	[LATIN EPIGRAPHIC LETTER REVERSED F]
			case 0xFF26: // Ｆ	[FULLWIDTH LATIN CAPITAL LETTER F]
				outString += "F";
				break;
			case 0x192: // ƒ	[LATIN SMALL LETTER F WITH HOOK]
			case 0x1D6E: // ᵮ	[LATIN SMALL LETTER F WITH MIDDLE TILDE]
			case 0x1D82: // ᶂ	[LATIN SMALL LETTER F WITH PALATAL HOOK]
			case 0x1E1F: // ḟ	[LATIN SMALL LETTER F WITH DOT ABOVE]
			case 0x1E9B: // ẛ	[LATIN SMALL LETTER LONG S WITH DOT ABOVE]
			case 0x24D5: // ⓕ	[CIRCLED LATIN SMALL LETTER F]
			case 0xA77C: // ꝼ	[LATIN SMALL LETTER INSULAR F]
			case 0xFF46: // ｆ	[FULLWIDTH LATIN SMALL LETTER F]
				outString += "f";
				break;
			case 0x24A1: // ⒡	[PARENTHESIZED LATIN SMALL LETTER F]
				outString += "(";
				outString += "f";
				outString += ")";
				break;
			case 0xFB00: // ﬀ	[LATIN SMALL LIGATURE FF]
				outString += "f";
				outString += "f";
				break;
			case 0xFB03: // ﬃ	[LATIN SMALL LIGATURE FFI]
				outString += "f";
				outString += "f";
				outString += "i";
				break;
			case 0xFB04: // ﬄ	[LATIN SMALL LIGATURE FFL]
				outString += "f";
				outString += "f";
				outString += "l";
				break;
			case 0xFB01: // ﬁ	[LATIN SMALL LIGATURE FI]
				outString += "f";
				outString += "i";
				break;
			case 0xFB02: // ﬂ	[LATIN SMALL LIGATURE FL]
				outString += "f";
				outString += "l";
				break;
			case 0x11C: // Ĝ	[LATIN CAPITAL LETTER G WITH CIRCUMFLEX]
			case 0x11E: // Ğ	[LATIN CAPITAL LETTER G WITH BREVE]
			case 0x120: // Ġ	[LATIN CAPITAL LETTER G WITH DOT ABOVE]
			case 0x122: // Ģ	[LATIN CAPITAL LETTER G WITH CEDILLA]
			case 0x193: // Ɠ	[LATIN CAPITAL LETTER G WITH HOOK]
			case 0x1E4: // Ǥ	[LATIN CAPITAL LETTER G WITH STROKE]
			case 0x1E5: // ǥ	[LATIN SMALL LETTER G WITH STROKE]
			case 0x1E6: // Ǧ	[LATIN CAPITAL LETTER G WITH CARON]
			case 0x1E7: // ǧ	[LATIN SMALL LETTER G WITH CARON]
			case 0x1F4: // Ǵ	[LATIN CAPITAL LETTER G WITH ACUTE]
			case 0x262: // ɢ	[LATIN LETTER SMALL CAPITAL G]
			case 0x29B: // ʛ	[LATIN LETTER SMALL CAPITAL G WITH HOOK]
			case 0x1E20: // Ḡ	[LATIN CAPITAL LETTER G WITH MACRON]
			case 0x24BC: // Ⓖ	[CIRCLED LATIN CAPITAL LETTER G]
			case 0xA77D: // Ᵹ	[LATIN CAPITAL LETTER INSULAR G]
			case 0xA77E: // Ꝿ	[LATIN CAPITAL LETTER TURNED INSULAR G]
			case 0xFF27: // Ｇ	[FULLWIDTH LATIN CAPITAL LETTER G]
				outString += "G";
				break;
			case 0x11D: // ĝ	[LATIN SMALL LETTER G WITH CIRCUMFLEX]
			case 0x11F: // ğ	[LATIN SMALL LETTER G WITH BREVE]
			case 0x121: // ġ	[LATIN SMALL LETTER G WITH DOT ABOVE]
			case 0x123: // ģ	[LATIN SMALL LETTER G WITH CEDILLA]
			case 0x1F5: // ǵ	[LATIN SMALL LETTER G WITH ACUTE]
			case 0x260: // ɠ	[LATIN SMALL LETTER G WITH HOOK]
			case 0x261: // ɡ	[LATIN SMALL LETTER SCRIPT G]
			case 0x1D77: // ᵷ	[LATIN SMALL LETTER TURNED G]
			case 0x1D79: // ᵹ	[LATIN SMALL LETTER INSULAR G]
			case 0x1D83: // ᶃ	[LATIN SMALL LETTER G WITH PALATAL HOOK]
			case 0x1E21: // ḡ	[LATIN SMALL LETTER G WITH MACRON]
			case 0x24D6: // ⓖ	[CIRCLED LATIN SMALL LETTER G]
			case 0xA77F: // ꝿ	[LATIN SMALL LETTER TURNED INSULAR G]
			case 0xFF47: // ｇ	[FULLWIDTH LATIN SMALL LETTER G]
				outString += "g";
				break;
			case 0x24A2: // ⒢	[PARENTHESIZED LATIN SMALL LETTER G]
				outString += "(";
				outString += "g";
				outString += ")";
				break;
			case 0x124: // Ĥ	[LATIN CAPITAL LETTER H WITH CIRCUMFLEX]
			case 0x126: // Ħ	[LATIN CAPITAL LETTER H WITH STROKE]
			case 0x21E: // Ȟ	[LATIN CAPITAL LETTER H WITH CARON]
			case 0x29C: // ʜ	[LATIN LETTER SMALL CAPITAL H]
			case 0x1E22: // Ḣ	[LATIN CAPITAL LETTER H WITH DOT ABOVE]
			case 0x1E24: // Ḥ	[LATIN CAPITAL LETTER H WITH DOT BELOW]
			case 0x1E26: // Ḧ	[LATIN CAPITAL LETTER H WITH DIAERESIS]
			case 0x1E28: // Ḩ	[LATIN CAPITAL LETTER H WITH CEDILLA]
			case 0x1E2A: // Ḫ	[LATIN CAPITAL LETTER H WITH BREVE BELOW]
			case 0x24BD: // Ⓗ	[CIRCLED LATIN CAPITAL LETTER H]
			case 0x2C67: // Ⱨ	[LATIN CAPITAL LETTER H WITH DESCENDER]
			case 0x2C75: // Ⱶ	[LATIN CAPITAL LETTER HALF H]
			case 0xFF28: // Ｈ	[FULLWIDTH LATIN CAPITAL LETTER H]
				outString += "H";
				break;
			case 0x125: // ĥ	[LATIN SMALL LETTER H WITH CIRCUMFLEX]
			case 0x127: // ħ	[LATIN SMALL LETTER H WITH STROKE]
			case 0x21F: // ȟ	[LATIN SMALL LETTER H WITH CARON]
			case 0x265: // ɥ	[LATIN SMALL LETTER TURNED H]
			case 0x266: // ɦ	[LATIN SMALL LETTER H WITH HOOK]
			case 0x2AE: // ʮ	[LATIN SMALL LETTER TURNED H WITH FISHHOOK]
			case 0x2AF: // ʯ	[LATIN SMALL LETTER TURNED H WITH FISHHOOK AND TAIL]
			case 0x1E23: // ḣ	[LATIN SMALL LETTER H WITH DOT ABOVE]
			case 0x1E25: // ḥ	[LATIN SMALL LETTER H WITH DOT BELOW]
			case 0x1E27: // ḧ	[LATIN SMALL LETTER H WITH DIAERESIS]
			case 0x1E29: // ḩ	[LATIN SMALL LETTER H WITH CEDILLA]
			case 0x1E2B: // ḫ	[LATIN SMALL LETTER H WITH BREVE BELOW]
			case 0x1E96: // ẖ	[LATIN SMALL LETTER H WITH LINE BELOW]
			case 0x24D7: // ⓗ	[CIRCLED LATIN SMALL LETTER H]
			case 0x2C68: // ⱨ	[LATIN SMALL LETTER H WITH DESCENDER]
			case 0x2C76: // ⱶ	[LATIN SMALL LETTER HALF H]
			case 0xFF48: // ｈ	[FULLWIDTH LATIN SMALL LETTER H]
				outString += "h";
				break;
			case 0x1F6: // Ƕ	http;//en.wikipedia.org/wiki/Hwair	[LATIN CAPITAL LETTER HWAIR]
				outString += "H";
				outString += "V";
				break;
			case 0x24A3: // ⒣	[PARENTHESIZED LATIN SMALL LETTER H]
				outString += "(";
				outString += "h";
				outString += ")";
				break;
			case 0x195: // ƕ	[LATIN SMALL LETTER HV]
				outString += "h";
				outString += "v";
				break;
			case 0xCC: // Ì	[LATIN CAPITAL LETTER I WITH GRAVE]
			case 0xCD: // Í	[LATIN CAPITAL LETTER I WITH ACUTE]
			case 0xCE: // Î	[LATIN CAPITAL LETTER I WITH CIRCUMFLEX]
			case 0xCF: // Ï	[LATIN CAPITAL LETTER I WITH DIAERESIS]
			case 0x128: // Ĩ	[LATIN CAPITAL LETTER I WITH TILDE]
			case 0x12A: // Ī	[LATIN CAPITAL LETTER I WITH MACRON]
			case 0x12C: // Ĭ	[LATIN CAPITAL LETTER I WITH BREVE]
			case 0x12E: // Į	[LATIN CAPITAL LETTER I WITH OGONEK]
			case 0x130: // İ	[LATIN CAPITAL LETTER I WITH DOT ABOVE]
			case 0x196: // Ɩ	[LATIN CAPITAL LETTER IOTA]
			case 0x197: // Ɨ	[LATIN CAPITAL LETTER I WITH STROKE]
			case 0x1CF: // Ǐ	[LATIN CAPITAL LETTER I WITH CARON]
			case 0x208: // Ȉ	[LATIN CAPITAL LETTER I WITH DOUBLE GRAVE]
			case 0x20A: // Ȋ	[LATIN CAPITAL LETTER I WITH INVERTED BREVE]
			case 0x26A: // ɪ	[LATIN LETTER SMALL CAPITAL I]
			case 0x1D7B: // ᵻ	[LATIN SMALL CAPITAL LETTER I WITH STROKE]
			case 0x1E2C: // Ḭ	[LATIN CAPITAL LETTER I WITH TILDE BELOW]
			case 0x1E2E: // Ḯ	[LATIN CAPITAL LETTER I WITH DIAERESIS AND ACUTE]
			case 0x1EC8: // Ỉ	[LATIN CAPITAL LETTER I WITH HOOK ABOVE]
			case 0x1ECA: // Ị	[LATIN CAPITAL LETTER I WITH DOT BELOW]
			case 0x24BE: // Ⓘ	[CIRCLED LATIN CAPITAL LETTER I]
			case 0xA7FE: // ꟾ	[LATIN EPIGRAPHIC LETTER I LONGA]
			case 0xFF29: // Ｉ	[FULLWIDTH LATIN CAPITAL LETTER I]
				outString += "I";
				break;
			case 0xEC: // ì	[LATIN SMALL LETTER I WITH GRAVE]
			case 0xED: // í	[LATIN SMALL LETTER I WITH ACUTE]
			case 0xEE: // î	[LATIN SMALL LETTER I WITH CIRCUMFLEX]
			case 0xEF: // ï	[LATIN SMALL LETTER I WITH DIAERESIS]
			case 0x129: // ĩ	[LATIN SMALL LETTER I WITH TILDE]
			case 0x12B: // ī	[LATIN SMALL LETTER I WITH MACRON]
			case 0x12D: // ĭ	[LATIN SMALL LETTER I WITH BREVE]
			case 0x12F: // į	[LATIN SMALL LETTER I WITH OGONEK]
			case 0x131: // ı	[LATIN SMALL LETTER DOTLESS I]
			case 0x1D0: // ǐ	[LATIN SMALL LETTER I WITH CARON]
			case 0x209: // ȉ	[LATIN SMALL LETTER I WITH DOUBLE GRAVE]
			case 0x20B: // ȋ	[LATIN SMALL LETTER I WITH INVERTED BREVE]
			case 0x268: // ɨ	[LATIN SMALL LETTER I WITH STROKE]
			case 0x1D09: // ᴉ	[LATIN SMALL LETTER TURNED I]
			case 0x1D62: // ᵢ	[LATIN SUBSCRIPT SMALL LETTER I]
			case 0x1D7C: // ᵼ	[LATIN SMALL LETTER IOTA WITH STROKE]
			case 0x1D96: // ᶖ	[LATIN SMALL LETTER I WITH RETROFLEX HOOK]
			case 0x1E2D: // ḭ	[LATIN SMALL LETTER I WITH TILDE BELOW]
			case 0x1E2F: // ḯ	[LATIN SMALL LETTER I WITH DIAERESIS AND ACUTE]
			case 0x1EC9: // ỉ	[LATIN SMALL LETTER I WITH HOOK ABOVE]
			case 0x1ECB: // ị	[LATIN SMALL LETTER I WITH DOT BELOW]
			case 0x2071: // ⁱ	[SUPERSCRIPT LATIN SMALL LETTER I]
			case 0x24D8: // ⓘ	[CIRCLED LATIN SMALL LETTER I]
			case 0xFF49: // ｉ	[FULLWIDTH LATIN SMALL LETTER I]
				outString += "i";
				break;
			case 0x132: // Ĳ	[LATIN CAPITAL LIGATURE IJ]
				outString += "I";
				outString += "J";
				break;
			case 0x24A4: // ⒤	[PARENTHESIZED LATIN SMALL LETTER I]
				outString += "(";
				outString += "i";
				outString += ")";
				break;
			case 0x133: // ĳ	[LATIN SMALL LIGATURE IJ]
				outString += "i";
				outString += "j";
				break;
			case 0x134: // Ĵ	[LATIN CAPITAL LETTER J WITH CIRCUMFLEX]
			case 0x248: // Ɉ	[LATIN CAPITAL LETTER J WITH STROKE]
			case 0x1D0A: // ᴊ	[LATIN LETTER SMALL CAPITAL J]
			case 0x24BF: // Ⓙ	[CIRCLED LATIN CAPITAL LETTER J]
			case 0xFF2A: // Ｊ	[FULLWIDTH LATIN CAPITAL LETTER J]
				outString += "J";
				break;
			case 0x135: // ĵ	[LATIN SMALL LETTER J WITH CIRCUMFLEX]
			case 0x1F0: // ǰ	[LATIN SMALL LETTER J WITH CARON]
			case 0x237: // ȷ	[LATIN SMALL LETTER DOTLESS J]
			case 0x249: // ɉ	[LATIN SMALL LETTER J WITH STROKE]
			case 0x25F: // ɟ	[LATIN SMALL LETTER DOTLESS J WITH STROKE]
			case 0x284: // ʄ	[LATIN SMALL LETTER DOTLESS J WITH STROKE AND HOOK]
			case 0x29D: // ʝ	[LATIN SMALL LETTER J WITH CROSSED-TAIL]
			case 0x24D9: // ⓙ	[CIRCLED LATIN SMALL LETTER J]
			case 0x2C7C: // ⱼ	[LATIN SUBSCRIPT SMALL LETTER J]
			case 0xFF4A: // ｊ	[FULLWIDTH LATIN SMALL LETTER J]
				outString += "j";
				break;
			case 0x24A5: // ⒥	[PARENTHESIZED LATIN SMALL LETTER J]
				outString += "(";
				outString += "j";
				outString += ")";
				break;
			case 0x136: // Ķ	[LATIN CAPITAL LETTER K WITH CEDILLA]
			case 0x198: // Ƙ	[LATIN CAPITAL LETTER K WITH HOOK]
			case 0x1E8: // Ǩ	[LATIN CAPITAL LETTER K WITH CARON]
			case 0x1D0B: // ᴋ	[LATIN LETTER SMALL CAPITAL K]
			case 0x1E30: // Ḱ	[LATIN CAPITAL LETTER K WITH ACUTE]
			case 0x1E32: // Ḳ	[LATIN CAPITAL LETTER K WITH DOT BELOW]
			case 0x1E34: // Ḵ	[LATIN CAPITAL LETTER K WITH LINE BELOW]
			case 0x24C0: // Ⓚ	[CIRCLED LATIN CAPITAL LETTER K]
			case 0x2C69: // Ⱪ	[LATIN CAPITAL LETTER K WITH DESCENDER]
			case 0xA740: // Ꝁ	[LATIN CAPITAL LETTER K WITH STROKE]
			case 0xA742: // Ꝃ	[LATIN CAPITAL LETTER K WITH DIAGONAL STROKE]
			case 0xA744: // Ꝅ	[LATIN CAPITAL LETTER K WITH STROKE AND DIAGONAL STROKE]
			case 0xFF2B: // Ｋ	[FULLWIDTH LATIN CAPITAL LETTER K]
				outString += "K";
				break;
			case 0x137: // ķ	[LATIN SMALL LETTER K WITH CEDILLA]
			case 0x199: // ƙ	[LATIN SMALL LETTER K WITH HOOK]
			case 0x1E9: // ǩ	[LATIN SMALL LETTER K WITH CARON]
			case 0x29E: // ʞ	[LATIN SMALL LETTER TURNED K]
			case 0x1D84: // ᶄ	[LATIN SMALL LETTER K WITH PALATAL HOOK]
			case 0x1E31: // ḱ	[LATIN SMALL LETTER K WITH ACUTE]
			case 0x1E33: // ḳ	[LATIN SMALL LETTER K WITH DOT BELOW]
			case 0x1E35: // ḵ	[LATIN SMALL LETTER K WITH LINE BELOW]
			case 0x24DA: // ⓚ	[CIRCLED LATIN SMALL LETTER K]
			case 0x2C6A: // ⱪ	[LATIN SMALL LETTER K WITH DESCENDER]
			case 0xA741: // ꝁ	[LATIN SMALL LETTER K WITH STROKE]
			case 0xA743: // ꝃ	[LATIN SMALL LETTER K WITH DIAGONAL STROKE]
			case 0xA745: // ꝅ	[LATIN SMALL LETTER K WITH STROKE AND DIAGONAL STROKE]
			case 0xFF4B: // ｋ	[FULLWIDTH LATIN SMALL LETTER K]
				outString += "k";
				break;
			case 0x24A6: // ⒦	[PARENTHESIZED LATIN SMALL LETTER K]
				outString += "(";
				outString += "k";
				outString += ")";
				break;
			case 0x139: // Ĺ	[LATIN CAPITAL LETTER L WITH ACUTE]
			case 0x13B: // Ļ	[LATIN CAPITAL LETTER L WITH CEDILLA]
			case 0x13D: // Ľ	[LATIN CAPITAL LETTER L WITH CARON]
			case 0x13F: // Ŀ	[LATIN CAPITAL LETTER L WITH MIDDLE DOT]
			case 0x141: // Ł	[LATIN CAPITAL LETTER L WITH STROKE]
			case 0x23D: // Ƚ	[LATIN CAPITAL LETTER L WITH BAR]
			case 0x29F: // ʟ	[LATIN LETTER SMALL CAPITAL L]
			case 0x1D0C: // ᴌ	[LATIN LETTER SMALL CAPITAL L WITH STROKE]
			case 0x1E36: // Ḷ	[LATIN CAPITAL LETTER L WITH DOT BELOW]
			case 0x1E38: // Ḹ	[LATIN CAPITAL LETTER L WITH DOT BELOW AND MACRON]
			case 0x1E3A: // Ḻ	[LATIN CAPITAL LETTER L WITH LINE BELOW]
			case 0x1E3C: // Ḽ	[LATIN CAPITAL LETTER L WITH CIRCUMFLEX BELOW]
			case 0x24C1: // Ⓛ	[CIRCLED LATIN CAPITAL LETTER L]
			case 0x2C60: // Ⱡ	[LATIN CAPITAL LETTER L WITH DOUBLE BAR]
			case 0x2C62: // Ɫ	[LATIN CAPITAL LETTER L WITH MIDDLE TILDE]
			case 0xA746: // Ꝇ	[LATIN CAPITAL LETTER BROKEN L]
			case 0xA748: // Ꝉ	[LATIN CAPITAL LETTER L WITH HIGH STROKE]
			case 0xA780: // Ꞁ	[LATIN CAPITAL LETTER TURNED L]
			case 0xFF2C: // Ｌ	[FULLWIDTH LATIN CAPITAL LETTER L]
				outString += "L";
				break;
			case 0x13A: // ĺ	[LATIN SMALL LETTER L WITH ACUTE]
			case 0x13C: // ļ	[LATIN SMALL LETTER L WITH CEDILLA]
			case 0x13E: // ľ	[LATIN SMALL LETTER L WITH CARON]
			case 0x140: // ŀ	[LATIN SMALL LETTER L WITH MIDDLE DOT]
			case 0x142: // ł	[LATIN SMALL LETTER L WITH STROKE]
			case 0x19A: // ƚ	[LATIN SMALL LETTER L WITH BAR]
			case 0x234: // ȴ	[LATIN SMALL LETTER L WITH CURL]
			case 0x26B: // ɫ	[LATIN SMALL LETTER L WITH MIDDLE TILDE]
			case 0x26C: // ɬ	[LATIN SMALL LETTER L WITH BELT]
			case 0x26D: // ɭ	[LATIN SMALL LETTER L WITH RETROFLEX HOOK]
			case 0x1D85: // ᶅ	[LATIN SMALL LETTER L WITH PALATAL HOOK]
			case 0x1E37: // ḷ	[LATIN SMALL LETTER L WITH DOT BELOW]
			case 0x1E39: // ḹ	[LATIN SMALL LETTER L WITH DOT BELOW AND MACRON]
			case 0x1E3B: // ḻ	[LATIN SMALL LETTER L WITH LINE BELOW]
			case 0x1E3D: // ḽ	[LATIN SMALL LETTER L WITH CIRCUMFLEX BELOW]
			case 0x24DB: // ⓛ	[CIRCLED LATIN SMALL LETTER L]
			case 0x2C61: // ⱡ	[LATIN SMALL LETTER L WITH DOUBLE BAR]
			case 0xA747: // ꝇ	[LATIN SMALL LETTER BROKEN L]
			case 0xA749: // ꝉ	[LATIN SMALL LETTER L WITH HIGH STROKE]
			case 0xA781: // ꞁ	[LATIN SMALL LETTER TURNED L]
			case 0xFF4C: // ｌ	[FULLWIDTH LATIN SMALL LETTER L]
				outString += "l";
				break;
			case 0x1C7: // Ǉ	[LATIN CAPITAL LETTER LJ]
				outString += "L";
				outString += "J";
				break;
			case 0x1EFA: // Ỻ	[LATIN CAPITAL LETTER MIDDLE-WELSH LL]
				outString += "L";
				outString += "L";
				break;
			case 0x1C8: // ǈ	[LATIN CAPITAL LETTER L WITH SMALL LETTER J]
				outString += "L";
				outString += "j";
				break;
			case 0x24A7: // ⒧	[PARENTHESIZED LATIN SMALL LETTER L]
				outString += "(";
				outString += "l";
				outString += ")";
				break;
			case 0x1C9: // ǉ	[LATIN SMALL LETTER LJ]
				outString += "l";
				outString += "j";
				break;
			case 0x1EFB: // ỻ	[LATIN SMALL LETTER MIDDLE-WELSH LL]
				outString += "l";
				outString += "l";
				break;
			case 0x2AA: // ʪ	[LATIN SMALL LETTER LS DIGRAPH]
				outString += "l";
				outString += "s";
				break;
			case 0x2AB: // ʫ	[LATIN SMALL LETTER LZ DIGRAPH]
				outString += "l";
				outString += "z";
				break;
			case 0x19C: // Ɯ	[LATIN CAPITAL LETTER TURNED M]
			case 0x1D0D: // ᴍ	[LATIN LETTER SMALL CAPITAL M]
			case 0x1E3E: // Ḿ	[LATIN CAPITAL LETTER M WITH ACUTE]
			case 0x1E40: // Ṁ	[LATIN CAPITAL LETTER M WITH DOT ABOVE]
			case 0x1E42: // Ṃ	[LATIN CAPITAL LETTER M WITH DOT BELOW]
			case 0x24C2: // Ⓜ	[CIRCLED LATIN CAPITAL LETTER M]
			case 0x2C6E: // Ɱ	[LATIN CAPITAL LETTER M WITH HOOK]
			case 0xA7FD: // ꟽ	[LATIN EPIGRAPHIC LETTER INVERTED M]
			case 0xA7FF: // ꟿ	[LATIN EPIGRAPHIC LETTER ARCHAIC M]
			case 0xFF2D: // Ｍ	[FULLWIDTH LATIN CAPITAL LETTER M]
				outString += "M";
				break;
			case 0x26F: // ɯ	[LATIN SMALL LETTER TURNED M]
			case 0x270: // ɰ	[LATIN SMALL LETTER TURNED M WITH LONG LEG]
			case 0x271: // ɱ	[LATIN SMALL LETTER M WITH HOOK]
			case 0x1D6F: // ᵯ	[LATIN SMALL LETTER M WITH MIDDLE TILDE]
			case 0x1D86: // ᶆ	[LATIN SMALL LETTER M WITH PALATAL HOOK]
			case 0x1E3F: // ḿ	[LATIN SMALL LETTER M WITH ACUTE]
			case 0x1E41: // ṁ	[LATIN SMALL LETTER M WITH DOT ABOVE]
			case 0x1E43: // ṃ	[LATIN SMALL LETTER M WITH DOT BELOW]
			case 0x24DC: // ⓜ	[CIRCLED LATIN SMALL LETTER M]
			case 0xFF4D: // ｍ	[FULLWIDTH LATIN SMALL LETTER M]
				outString += "m";
				break;
			case 0x24A8: // ⒨	[PARENTHESIZED LATIN SMALL LETTER M]
				outString += "(";
				outString += "m";
				outString += ")";
				break;
			case 0xD1: // Ñ	[LATIN CAPITAL LETTER N WITH TILDE]
			case 0x143: // Ń	[LATIN CAPITAL LETTER N WITH ACUTE]
			case 0x145: // Ņ	[LATIN CAPITAL LETTER N WITH CEDILLA]
			case 0x147: // Ň	[LATIN CAPITAL LETTER N WITH CARON]
			case 0x14A: // Ŋ	http;//en.wikipedia.org/wiki/Eng_(letter)	[LATIN CAPITAL LETTER ENG]
			case 0x19D: // Ɲ	[LATIN CAPITAL LETTER N WITH LEFT HOOK]
			case 0x1F8: // Ǹ	[LATIN CAPITAL LETTER N WITH GRAVE]
			case 0x220: // Ƞ	[LATIN CAPITAL LETTER N WITH LONG RIGHT LEG]
			case 0x274: // ɴ	[LATIN LETTER SMALL CAPITAL N]
			case 0x1D0E: // ᴎ	[LATIN LETTER SMALL CAPITAL REVERSED N]
			case 0x1E44: // Ṅ	[LATIN CAPITAL LETTER N WITH DOT ABOVE]
			case 0x1E46: // Ṇ	[LATIN CAPITAL LETTER N WITH DOT BELOW]
			case 0x1E48: // Ṉ	[LATIN CAPITAL LETTER N WITH LINE BELOW]
			case 0x1E4A: // Ṋ	[LATIN CAPITAL LETTER N WITH CIRCUMFLEX BELOW]
			case 0x24C3: // Ⓝ	[CIRCLED LATIN CAPITAL LETTER N]
			case 0xFF2E: // Ｎ	[FULLWIDTH LATIN CAPITAL LETTER N]
				outString += "N";
				break;
			case 0xF1: // ñ	[LATIN SMALL LETTER N WITH TILDE]
			case 0x144: // ń	[LATIN SMALL LETTER N WITH ACUTE]
			case 0x146: // ņ	[LATIN SMALL LETTER N WITH CEDILLA]
			case 0x148: // ň	[LATIN SMALL LETTER N WITH CARON]
			case 0x149: // ŉ	[LATIN SMALL LETTER N PRECEDED BY APOSTROPHE]
			case 0x14B: // ŋ	http;//en.wikipedia.org/wiki/Eng_(letter)	[LATIN SMALL LETTER ENG]
			case 0x19E: // ƞ	[LATIN SMALL LETTER N WITH LONG RIGHT LEG]
			case 0x1F9: // ǹ	[LATIN SMALL LETTER N WITH GRAVE]
			case 0x235: // ȵ	[LATIN SMALL LETTER N WITH CURL]
			case 0x272: // ɲ	[LATIN SMALL LETTER N WITH LEFT HOOK]
			case 0x273: // ɳ	[LATIN SMALL LETTER N WITH RETROFLEX HOOK]
			case 0x1D70: // ᵰ	[LATIN SMALL LETTER N WITH MIDDLE TILDE]
			case 0x1D87: // ᶇ	[LATIN SMALL LETTER N WITH PALATAL HOOK]
			case 0x1E45: // ṅ	[LATIN SMALL LETTER N WITH DOT ABOVE]
			case 0x1E47: // ṇ	[LATIN SMALL LETTER N WITH DOT BELOW]
			case 0x1E49: // ṉ	[LATIN SMALL LETTER N WITH LINE BELOW]
			case 0x1E4B: // ṋ	[LATIN SMALL LETTER N WITH CIRCUMFLEX BELOW]
			case 0x207F: // ⁿ	[SUPERSCRIPT LATIN SMALL LETTER N]
			case 0x24DD: // ⓝ	[CIRCLED LATIN SMALL LETTER N]
			case 0xFF4E: // ｎ	[FULLWIDTH LATIN SMALL LETTER N]
				outString += "n";
				break;
			case 0x1CA: // Ǌ	[LATIN CAPITAL LETTER NJ]
				outString += "N";
				outString += "J";
				break;
			case 0x1CB: // ǋ	[LATIN CAPITAL LETTER N WITH SMALL LETTER J]
				outString += "N";
				outString += "j";
				break;
			case 0x24A9: // ⒩	[PARENTHESIZED LATIN SMALL LETTER N]
				outString += "(";
				outString += "n";
				outString += ")";
				break;
			case 0x1CC: // ǌ	[LATIN SMALL LETTER NJ]
				outString += "n";
				outString += "j";
				break;
			case 0xD2: // Ò	[LATIN CAPITAL LETTER O WITH GRAVE]
			case 0xD3: // Ó	[LATIN CAPITAL LETTER O WITH ACUTE]
			case 0xD4: // Ô	[LATIN CAPITAL LETTER O WITH CIRCUMFLEX]
			case 0xD5: // Õ	[LATIN CAPITAL LETTER O WITH TILDE]
			case 0xD6: // Ö	[LATIN CAPITAL LETTER O WITH DIAERESIS]
			case 0xD8: // Ø	[LATIN CAPITAL LETTER O WITH STROKE]
			case 0x14C: // Ō	[LATIN CAPITAL LETTER O WITH MACRON]
			case 0x14E: // Ŏ	[LATIN CAPITAL LETTER O WITH BREVE]
			case 0x150: // Ő	[LATIN CAPITAL LETTER O WITH DOUBLE ACUTE]
			case 0x186: // Ɔ	[LATIN CAPITAL LETTER OPEN O]
			case 0x19F: // Ɵ	[LATIN CAPITAL LETTER O WITH MIDDLE TILDE]
			case 0x1A0: // Ơ	[LATIN CAPITAL LETTER O WITH HORN]
			case 0x1D1: // Ǒ	[LATIN CAPITAL LETTER O WITH CARON]
			case 0x1EA: // Ǫ	[LATIN CAPITAL LETTER O WITH OGONEK]
			case 0x1EC: // Ǭ	[LATIN CAPITAL LETTER O WITH OGONEK AND MACRON]
			case 0x1FE: // Ǿ	[LATIN CAPITAL LETTER O WITH STROKE AND ACUTE]
			case 0x20C: // Ȍ	[LATIN CAPITAL LETTER O WITH DOUBLE GRAVE]
			case 0x20E: // Ȏ	[LATIN CAPITAL LETTER O WITH INVERTED BREVE]
			case 0x22A: // Ȫ	[LATIN CAPITAL LETTER O WITH DIAERESIS AND MACRON]
			case 0x22C: // Ȭ	[LATIN CAPITAL LETTER O WITH TILDE AND MACRON]
			case 0x22E: // Ȯ	[LATIN CAPITAL LETTER O WITH DOT ABOVE]
			case 0x230: // Ȱ	[LATIN CAPITAL LETTER O WITH DOT ABOVE AND MACRON]
			case 0x1D0F: // ᴏ	[LATIN LETTER SMALL CAPITAL O]
			case 0x1D10: // ᴐ	[LATIN LETTER SMALL CAPITAL OPEN O]
			case 0x1E4C: // Ṍ	[LATIN CAPITAL LETTER O WITH TILDE AND ACUTE]
			case 0x1E4E: // Ṏ	[LATIN CAPITAL LETTER O WITH TILDE AND DIAERESIS]
			case 0x1E50: // Ṑ	[LATIN CAPITAL LETTER O WITH MACRON AND GRAVE]
			case 0x1E52: // Ṓ	[LATIN CAPITAL LETTER O WITH MACRON AND ACUTE]
			case 0x1ECC: // Ọ	[LATIN CAPITAL LETTER O WITH DOT BELOW]
			case 0x1ECE: // Ỏ	[LATIN CAPITAL LETTER O WITH HOOK ABOVE]
			case 0x1ED0: // Ố	[LATIN CAPITAL LETTER O WITH CIRCUMFLEX AND ACUTE]
			case 0x1ED2: // Ồ	[LATIN CAPITAL LETTER O WITH CIRCUMFLEX AND GRAVE]
			case 0x1ED4: // Ổ	[LATIN CAPITAL LETTER O WITH CIRCUMFLEX AND HOOK ABOVE]
			case 0x1ED6: // Ỗ	[LATIN CAPITAL LETTER O WITH CIRCUMFLEX AND TILDE]
			case 0x1ED8: // Ộ	[LATIN CAPITAL LETTER O WITH CIRCUMFLEX AND DOT BELOW]
			case 0x1EDA: // Ớ	[LATIN CAPITAL LETTER O WITH HORN AND ACUTE]
			case 0x1EDC: // Ờ	[LATIN CAPITAL LETTER O WITH HORN AND GRAVE]
			case 0x1EDE: // Ở	[LATIN CAPITAL LETTER O WITH HORN AND HOOK ABOVE]
			case 0x1EE0: // Ỡ	[LATIN CAPITAL LETTER O WITH HORN AND TILDE]
			case 0x1EE2: // Ợ	[LATIN CAPITAL LETTER O WITH HORN AND DOT BELOW]
			case 0x24C4: // Ⓞ	[CIRCLED LATIN CAPITAL LETTER O]
			case 0xA74A: // Ꝋ	[LATIN CAPITAL LETTER O WITH LONG STROKE OVERLAY]
			case 0xA74C: // Ꝍ	[LATIN CAPITAL LETTER O WITH LOOP]
			case 0xFF2F: // Ｏ	[FULLWIDTH LATIN CAPITAL LETTER O]
				outString += "O";
				break;
			case 0xF2: // ò	[LATIN SMALL LETTER O WITH GRAVE]
			case 0xF3: // ó	[LATIN SMALL LETTER O WITH ACUTE]
			case 0xF4: // ô	[LATIN SMALL LETTER O WITH CIRCUMFLEX]
			case 0xF5: // õ	[LATIN SMALL LETTER O WITH TILDE]
			case 0xF6: // ö	[LATIN SMALL LETTER O WITH DIAERESIS]
			case 0xF8: // ø	[LATIN SMALL LETTER O WITH STROKE]
			case 0x14D: // ō	[LATIN SMALL LETTER O WITH MACRON]
			case 0x14F: // ŏ	[LATIN SMALL LETTER O WITH BREVE]
			case 0x151: // ő	[LATIN SMALL LETTER O WITH DOUBLE ACUTE]
			case 0x1A1: // ơ	[LATIN SMALL LETTER O WITH HORN]
			case 0x1D2: // ǒ	[LATIN SMALL LETTER O WITH CARON]
			case 0x1EB: // ǫ	[LATIN SMALL LETTER O WITH OGONEK]
			case 0x1ED: // ǭ	[LATIN SMALL LETTER O WITH OGONEK AND MACRON]
			case 0x1FF: // ǿ	[LATIN SMALL LETTER O WITH STROKE AND ACUTE]
			case 0x20D: // ȍ	[LATIN SMALL LETTER O WITH DOUBLE GRAVE]
			case 0x20F: // ȏ	[LATIN SMALL LETTER O WITH INVERTED BREVE]
			case 0x22B: // ȫ	[LATIN SMALL LETTER O WITH DIAERESIS AND MACRON]
			case 0x22D: // ȭ	[LATIN SMALL LETTER O WITH TILDE AND MACRON]
			case 0x22F: // ȯ	[LATIN SMALL LETTER O WITH DOT ABOVE]
			case 0x231: // ȱ	[LATIN SMALL LETTER O WITH DOT ABOVE AND MACRON]
			case 0x254: // ɔ	[LATIN SMALL LETTER OPEN O]
			case 0x275: // ɵ	[LATIN SMALL LETTER BARRED O]
			case 0x1D16: // ᴖ	[LATIN SMALL LETTER TOP HALF O]
			case 0x1D17: // ᴗ	[LATIN SMALL LETTER BOTTOM HALF O]
			case 0x1D97: // ᶗ	[LATIN SMALL LETTER OPEN O WITH RETROFLEX HOOK]
			case 0x1E4D: // ṍ	[LATIN SMALL LETTER O WITH TILDE AND ACUTE]
			case 0x1E4F: // ṏ	[LATIN SMALL LETTER O WITH TILDE AND DIAERESIS]
			case 0x1E51: // ṑ	[LATIN SMALL LETTER O WITH MACRON AND GRAVE]
			case 0x1E53: // ṓ	[LATIN SMALL LETTER O WITH MACRON AND ACUTE]
			case 0x1ECD: // ọ	[LATIN SMALL LETTER O WITH DOT BELOW]
			case 0x1ECF: // ỏ	[LATIN SMALL LETTER O WITH HOOK ABOVE]
			case 0x1ED1: // ố	[LATIN SMALL LETTER O WITH CIRCUMFLEX AND ACUTE]
			case 0x1ED3: // ồ	[LATIN SMALL LETTER O WITH CIRCUMFLEX AND GRAVE]
			case 0x1ED5: // ổ	[LATIN SMALL LETTER O WITH CIRCUMFLEX AND HOOK ABOVE]
			case 0x1ED7: // ỗ	[LATIN SMALL LETTER O WITH CIRCUMFLEX AND TILDE]
			case 0x1ED9: // ộ	[LATIN SMALL LETTER O WITH CIRCUMFLEX AND DOT BELOW]
			case 0x1EDB: // ớ	[LATIN SMALL LETTER O WITH HORN AND ACUTE]
			case 0x1EDD: // ờ	[LATIN SMALL LETTER O WITH HORN AND GRAVE]
			case 0x1EDF: // ở	[LATIN SMALL LETTER O WITH HORN AND HOOK ABOVE]
			case 0x1EE1: // ỡ	[LATIN SMALL LETTER O WITH HORN AND TILDE]
			case 0x1EE3: // ợ	[LATIN SMALL LETTER O WITH HORN AND DOT BELOW]
			case 0x2092: // ₒ	[LATIN SUBSCRIPT SMALL LETTER O]
			case 0x24DE: // ⓞ	[CIRCLED LATIN SMALL LETTER O]
			case 0x2C7A: // ⱺ	[LATIN SMALL LETTER O WITH LOW RING INSIDE]
			case 0xA74B: // ꝋ	[LATIN SMALL LETTER O WITH LONG STROKE OVERLAY]
			case 0xA74D: // ꝍ	[LATIN SMALL LETTER O WITH LOOP]
			case 0xFF4F: // ｏ	[FULLWIDTH LATIN SMALL LETTER O]
				outString += "o";
				break;
			case 0x152: // Œ	[LATIN CAPITAL LIGATURE OE]
			case 0x276: // ɶ	[LATIN LETTER SMALL CAPITAL OE]
				outString += "O";
				outString += "E";
				break;
			case 0xA74E: // Ꝏ	[LATIN CAPITAL LETTER OO]
				outString += "O";
				outString += "O";
				break;
			case 0x222: // Ȣ	http;//en.wikipedia.org/wiki/OU	[LATIN CAPITAL LETTER OU]
			case 0x1D15: // ᴕ	[LATIN LETTER SMALL CAPITAL OU]
				outString += "O";
				outString += "U";
				break;
			case 0x24AA: // ⒪	[PARENTHESIZED LATIN SMALL LETTER O]
				outString += "(";
				outString += "o";
				outString += ")";
				break;
			case 0x153: // œ	[LATIN SMALL LIGATURE OE]
			case 0x1D14: // ᴔ	[LATIN SMALL LETTER TURNED OE]
				outString += "o";
				outString += "e";
				break;
			case 0xA74F: // ꝏ	[LATIN SMALL LETTER OO]
				outString += "o";
				outString += "o";
				break;
			case 0x223: // ȣ	http;//en.wikipedia.org/wiki/OU	[LATIN SMALL LETTER OU]
				outString += "o";
				outString += "u";
				break;
			case 0x1A4: // Ƥ	[LATIN CAPITAL LETTER P WITH HOOK]
			case 0x1D18: // ᴘ	[LATIN LETTER SMALL CAPITAL P]
			case 0x1E54: // Ṕ	[LATIN CAPITAL LETTER P WITH ACUTE]
			case 0x1E56: // Ṗ	[LATIN CAPITAL LETTER P WITH DOT ABOVE]
			case 0x24C5: // Ⓟ	[CIRCLED LATIN CAPITAL LETTER P]
			case 0x2C63: // Ᵽ	[LATIN CAPITAL LETTER P WITH STROKE]
			case 0xA750: // Ꝑ	[LATIN CAPITAL LETTER P WITH STROKE THROUGH DESCENDER]
			case 0xA752: // Ꝓ	[LATIN CAPITAL LETTER P WITH FLOURISH]
			case 0xA754: // Ꝕ	[LATIN CAPITAL LETTER P WITH SQUIRREL TAIL]
			case 0xFF30: // Ｐ	[FULLWIDTH LATIN CAPITAL LETTER P]
				outString += "P";
				break;
			case 0x1A5: // ƥ	[LATIN SMALL LETTER P WITH HOOK]
			case 0x1D71: // ᵱ	[LATIN SMALL LETTER P WITH MIDDLE TILDE]
			case 0x1D7D: // ᵽ	[LATIN SMALL LETTER P WITH STROKE]
			case 0x1D88: // ᶈ	[LATIN SMALL LETTER P WITH PALATAL HOOK]
			case 0x1E55: // ṕ	[LATIN SMALL LETTER P WITH ACUTE]
			case 0x1E57: // ṗ	[LATIN SMALL LETTER P WITH DOT ABOVE]
			case 0x24DF: // ⓟ	[CIRCLED LATIN SMALL LETTER P]
			case 0xA751: // ꝑ	[LATIN SMALL LETTER P WITH STROKE THROUGH DESCENDER]
			case 0xA753: // ꝓ	[LATIN SMALL LETTER P WITH FLOURISH]
			case 0xA755: // ꝕ	[LATIN SMALL LETTER P WITH SQUIRREL TAIL]
			case 0xA7FC: // ꟼ	[LATIN EPIGRAPHIC LETTER REVERSED P]
			case 0xFF50: // ｐ	[FULLWIDTH LATIN SMALL LETTER P]
				outString += "p";
				break;
			case 0x24AB: // ⒫	[PARENTHESIZED LATIN SMALL LETTER P]
				outString += "(";
				outString += "p";
				outString += ")";
				break;
			case 0x24A: // Ɋ	[LATIN CAPITAL LETTER SMALL Q WITH HOOK TAIL]
			case 0x24C6: // Ⓠ	[CIRCLED LATIN CAPITAL LETTER Q]
			case 0xA756: // Ꝗ	[LATIN CAPITAL LETTER Q WITH STROKE THROUGH DESCENDER]
			case 0xA758: // Ꝙ	[LATIN CAPITAL LETTER Q WITH DIAGONAL STROKE]
			case 0xFF31: // Ｑ	[FULLWIDTH LATIN CAPITAL LETTER Q]
				outString += "Q";
				break;
			case 0x138: // ĸ	http;//en.wikipedia.org/wiki/Kra_(letter)	[LATIN SMALL LETTER KRA]
			case 0x24B: // ɋ	[LATIN SMALL LETTER Q WITH HOOK TAIL]
			case 0x2A0: // ʠ	[LATIN SMALL LETTER Q WITH HOOK]
			case 0x24E0: // ⓠ	[CIRCLED LATIN SMALL LETTER Q]
			case 0xA757: // ꝗ	[LATIN SMALL LETTER Q WITH STROKE THROUGH DESCENDER]
			case 0xA759: // ꝙ	[LATIN SMALL LETTER Q WITH DIAGONAL STROKE]
			case 0xFF51: // ｑ	[FULLWIDTH LATIN SMALL LETTER Q]
				outString += "q";
				break;
			case 0x24AC: // ⒬	[PARENTHESIZED LATIN SMALL LETTER Q]
				outString += "(";
				outString += "q";
				outString += ")";
				break;
			case 0x239: // ȹ	[LATIN SMALL LETTER QP DIGRAPH]
				outString += "q";
				outString += "p";
				break;
			case 0x154: // Ŕ	[LATIN CAPITAL LETTER R WITH ACUTE]
			case 0x156: // Ŗ	[LATIN CAPITAL LETTER R WITH CEDILLA]
			case 0x158: // Ř	[LATIN CAPITAL LETTER R WITH CARON]
			case 0x210: // Ȓ	[LATIN CAPITAL LETTER R WITH DOUBLE GRAVE]
			case 0x212: // Ȓ	[LATIN CAPITAL LETTER R WITH INVERTED BREVE]
			case 0x24C: // Ɍ	[LATIN CAPITAL LETTER R WITH STROKE]
			case 0x280: // ʀ	[LATIN LETTER SMALL CAPITAL R]
			case 0x281: // ʁ	[LATIN LETTER SMALL CAPITAL INVERTED R]
			case 0x1D19: // ᴙ	[LATIN LETTER SMALL CAPITAL REVERSED R]
			case 0x1D1A: // ᴚ	[LATIN LETTER SMALL CAPITAL TURNED R]
			case 0x1E58: // Ṙ	[LATIN CAPITAL LETTER R WITH DOT ABOVE]
			case 0x1E5A: // Ṛ	[LATIN CAPITAL LETTER R WITH DOT BELOW]
			case 0x1E5C: // Ṝ	[LATIN CAPITAL LETTER R WITH DOT BELOW AND MACRON]
			case 0x1E5E: // Ṟ	[LATIN CAPITAL LETTER R WITH LINE BELOW]
			case 0x24C7: // Ⓡ	[CIRCLED LATIN CAPITAL LETTER R]
			case 0x2C64: // Ɽ	[LATIN CAPITAL LETTER R WITH TAIL]
			case 0xA75A: // Ꝛ	[LATIN CAPITAL LETTER R ROTUNDA]
			case 0xA782: // Ꞃ	[LATIN CAPITAL LETTER INSULAR R]
			case 0xFF32: // Ｒ	[FULLWIDTH LATIN CAPITAL LETTER R]
				outString += "R";
				break;
			case 0x155: // ŕ	[LATIN SMALL LETTER R WITH ACUTE]
			case 0x157: // ŗ	[LATIN SMALL LETTER R WITH CEDILLA]
			case 0x159: // ř	[LATIN SMALL LETTER R WITH CARON]
			case 0x211: // ȑ	[LATIN SMALL LETTER R WITH DOUBLE GRAVE]
			case 0x213: // ȓ	[LATIN SMALL LETTER R WITH INVERTED BREVE]
			case 0x24D: // ɍ	[LATIN SMALL LETTER R WITH STROKE]
			case 0x27C: // ɼ	[LATIN SMALL LETTER R WITH LONG LEG]
			case 0x27D: // ɽ	[LATIN SMALL LETTER R WITH TAIL]
			case 0x27E: // ɾ	[LATIN SMALL LETTER R WITH FISHHOOK]
			case 0x27F: // ɿ	[LATIN SMALL LETTER REVERSED R WITH FISHHOOK]
			case 0x1D63: // ᵣ	[LATIN SUBSCRIPT SMALL LETTER R]
			case 0x1D72: // ᵲ	[LATIN SMALL LETTER R WITH MIDDLE TILDE]
			case 0x1D73: // ᵳ	[LATIN SMALL LETTER R WITH FISHHOOK AND MIDDLE TILDE]
			case 0x1D89: // ᶉ	[LATIN SMALL LETTER R WITH PALATAL HOOK]
			case 0x1E59: // ṙ	[LATIN SMALL LETTER R WITH DOT ABOVE]
			case 0x1E5B: // ṛ	[LATIN SMALL LETTER R WITH DOT BELOW]
			case 0x1E5D: // ṝ	[LATIN SMALL LETTER R WITH DOT BELOW AND MACRON]
			case 0x1E5F: // ṟ	[LATIN SMALL LETTER R WITH LINE BELOW]
			case 0x24E1: // ⓡ	[CIRCLED LATIN SMALL LETTER R]
			case 0xA75B: // ꝛ	[LATIN SMALL LETTER R ROTUNDA]
			case 0xA783: // ꞃ	[LATIN SMALL LETTER INSULAR R]
			case 0xFF52: // ｒ	[FULLWIDTH LATIN SMALL LETTER R]
				outString += "r";
				break;
			case 0x24AD: // ⒭	[PARENTHESIZED LATIN SMALL LETTER R]
				outString += "(";
				outString += "r";
				outString += ")";
				break;
			case 0x15A: // Ś	[LATIN CAPITAL LETTER S WITH ACUTE]
			case 0x15C: // Ŝ	[LATIN CAPITAL LETTER S WITH CIRCUMFLEX]
			case 0x15E: // Ş	[LATIN CAPITAL LETTER S WITH CEDILLA]
			case 0x160: // Š	[LATIN CAPITAL LETTER S WITH CARON]
			case 0x218: // Ș	[LATIN CAPITAL LETTER S WITH COMMA BELOW]
			case 0x1E60: // Ṡ	[LATIN CAPITAL LETTER S WITH DOT ABOVE]
			case 0x1E62: // Ṣ	[LATIN CAPITAL LETTER S WITH DOT BELOW]
			case 0x1E64: // Ṥ	[LATIN CAPITAL LETTER S WITH ACUTE AND DOT ABOVE]
			case 0x1E66: // Ṧ	[LATIN CAPITAL LETTER S WITH CARON AND DOT ABOVE]
			case 0x1E68: // Ṩ	[LATIN CAPITAL LETTER S WITH DOT BELOW AND DOT ABOVE]
			case 0x24C8: // Ⓢ	[CIRCLED LATIN CAPITAL LETTER S]
			case 0xA731: // ꜱ	[LATIN LETTER SMALL CAPITAL S]
			case 0xA785: // ꞅ	[LATIN SMALL LETTER INSULAR S]
			case 0xFF33: // Ｓ	[FULLWIDTH LATIN CAPITAL LETTER S]
				outString += "S";
				break;
			case 0x15B: // ś	[LATIN SMALL LETTER S WITH ACUTE]
			case 0x15D: // ŝ	[LATIN SMALL LETTER S WITH CIRCUMFLEX]
			case 0x15F: // ş	[LATIN SMALL LETTER S WITH CEDILLA]
			case 0x161: // š	[LATIN SMALL LETTER S WITH CARON]
			case 0x17F: // ſ	http;//en.wikipedia.org/wiki/Long_S	[LATIN SMALL LETTER LONG S]
			case 0x219: // ș	[LATIN SMALL LETTER S WITH COMMA BELOW]
			case 0x23F: // ȿ	[LATIN SMALL LETTER S WITH SWASH TAIL]
			case 0x282: // ʂ	[LATIN SMALL LETTER S WITH HOOK]
			case 0x1D74: // ᵴ	[LATIN SMALL LETTER S WITH MIDDLE TILDE]
			case 0x1D8A: // ᶊ	[LATIN SMALL LETTER S WITH PALATAL HOOK]
			case 0x1E61: // ṡ	[LATIN SMALL LETTER S WITH DOT ABOVE]
			case 0x1E63: // ṣ	[LATIN SMALL LETTER S WITH DOT BELOW]
			case 0x1E65: // ṥ	[LATIN SMALL LETTER S WITH ACUTE AND DOT ABOVE]
			case 0x1E67: // ṧ	[LATIN SMALL LETTER S WITH CARON AND DOT ABOVE]
			case 0x1E69: // ṩ	[LATIN SMALL LETTER S WITH DOT BELOW AND DOT ABOVE]
			case 0x1E9C: // ẜ	[LATIN SMALL LETTER LONG S WITH DIAGONAL STROKE]
			case 0x1E9D: // ẝ	[LATIN SMALL LETTER LONG S WITH HIGH STROKE]
			case 0x24E2: // ⓢ	[CIRCLED LATIN SMALL LETTER S]
			case 0xA784: // Ꞅ	[LATIN CAPITAL LETTER INSULAR S]
			case 0xFF53: // ｓ	[FULLWIDTH LATIN SMALL LETTER S]
				outString += "s";
				break;
			case 0x1E9E: // ẞ	[LATIN CAPITAL LETTER SHARP S]
				outString += "S";
				outString += "S";
				break;
			case 0x24AE: // ⒮	[PARENTHESIZED LATIN SMALL LETTER S]
				outString += "(";
				outString += "s";
				outString += ")";
				break;
			case 0xDF: // ß	[LATIN SMALL LETTER SHARP S]
				outString += "s";
				outString += "s";
				break;
			case 0xFB06: // ﬆ	[LATIN SMALL LIGATURE ST]
				outString += "s";
				outString += "t";
				break;
			case 0x162: // Ţ	[LATIN CAPITAL LETTER T WITH CEDILLA]
			case 0x164: // Ť	[LATIN CAPITAL LETTER T WITH CARON]
			case 0x166: // Ŧ	[LATIN CAPITAL LETTER T WITH STROKE]
			case 0x1AC: // Ƭ	[LATIN CAPITAL LETTER T WITH HOOK]
			case 0x1AE: // Ʈ	[LATIN CAPITAL LETTER T WITH RETROFLEX HOOK]
			case 0x21A: // Ț	[LATIN CAPITAL LETTER T WITH COMMA BELOW]
			case 0x23E: // Ⱦ	[LATIN CAPITAL LETTER T WITH DIAGONAL STROKE]
			case 0x1D1B: // ᴛ	[LATIN LETTER SMALL CAPITAL T]
			case 0x1E6A: // Ṫ	[LATIN CAPITAL LETTER T WITH DOT ABOVE]
			case 0x1E6C: // Ṭ	[LATIN CAPITAL LETTER T WITH DOT BELOW]
			case 0x1E6E: // Ṯ	[LATIN CAPITAL LETTER T WITH LINE BELOW]
			case 0x1E70: // Ṱ	[LATIN CAPITAL LETTER T WITH CIRCUMFLEX BELOW]
			case 0x24C9: // Ⓣ	[CIRCLED LATIN CAPITAL LETTER T]
			case 0xA786: // Ꞇ	[LATIN CAPITAL LETTER INSULAR T]
			case 0xFF34: // Ｔ	[FULLWIDTH LATIN CAPITAL LETTER T]
				outString += "T";
				break;
			case 0x163: // ţ	[LATIN SMALL LETTER T WITH CEDILLA]
			case 0x165: // ť	[LATIN SMALL LETTER T WITH CARON]
			case 0x167: // ŧ	[LATIN SMALL LETTER T WITH STROKE]
			case 0x1AB: // ƫ	[LATIN SMALL LETTER T WITH PALATAL HOOK]
			case 0x1AD: // ƭ	[LATIN SMALL LETTER T WITH HOOK]
			case 0x21B: // ț	[LATIN SMALL LETTER T WITH COMMA BELOW]
			case 0x236: // ȶ	[LATIN SMALL LETTER T WITH CURL]
			case 0x287: // ʇ	[LATIN SMALL LETTER TURNED T]
			case 0x288: // ʈ	[LATIN SMALL LETTER T WITH RETROFLEX HOOK]
			case 0x1D75: // ᵵ	[LATIN SMALL LETTER T WITH MIDDLE TILDE]
			case 0x1E6B: // ṫ	[LATIN SMALL LETTER T WITH DOT ABOVE]
			case 0x1E6D: // ṭ	[LATIN SMALL LETTER T WITH DOT BELOW]
			case 0x1E6F: // ṯ	[LATIN SMALL LETTER T WITH LINE BELOW]
			case 0x1E71: // ṱ	[LATIN SMALL LETTER T WITH CIRCUMFLEX BELOW]
			case 0x1E97: // ẗ	[LATIN SMALL LETTER T WITH DIAERESIS]
			case 0x24E3: // ⓣ	[CIRCLED LATIN SMALL LETTER T]
			case 0x2C66: // ⱦ	[LATIN SMALL LETTER T WITH DIAGONAL STROKE]
			case 0xFF54: // ｔ	[FULLWIDTH LATIN SMALL LETTER T]
				outString += "t";
				break;
			case 0xDE: // Þ	[LATIN CAPITAL LETTER THORN]
			case 0xA766: // Ꝧ	[LATIN CAPITAL LETTER THORN WITH STROKE THROUGH DESCENDER]
				outString += "T";
				outString += "H";
				break;
			case 0xA728: // Ꜩ	[LATIN CAPITAL LETTER TZ]
				outString += "T";
				outString += "Z";
				break;
			case 0x24AF: // ⒯	[PARENTHESIZED LATIN SMALL LETTER T]
				outString += "(";
				outString += "t";
				outString += ")";
				break;
			case 0x2A8: // ʨ	[LATIN SMALL LETTER TC DIGRAPH WITH CURL]
				outString += "t";
				outString += "c";
				break;
			case 0xFE: // þ	[LATIN SMALL LETTER THORN]
			case 0x1D7A: // ᵺ	[LATIN SMALL LETTER TH WITH STRIKETHROUGH]
			case 0xA767: // ꝧ	[LATIN SMALL LETTER THORN WITH STROKE THROUGH DESCENDER]
				outString += "t";
				outString += "h";
				break;
			case 0x2A6: // ʦ	[LATIN SMALL LETTER TS DIGRAPH]
				outString += "t";
				outString += "s";
				break;
			case 0xA729: // ꜩ	[LATIN SMALL LETTER TZ]
				outString += "t";
				outString += "z";
				break;
			case 0xD9: // Ù	[LATIN CAPITAL LETTER U WITH GRAVE]
			case 0xDA: // Ú	[LATIN CAPITAL LETTER U WITH ACUTE]
			case 0xDB: // Û	[LATIN CAPITAL LETTER U WITH CIRCUMFLEX]
			case 0xDC: // Ü	[LATIN CAPITAL LETTER U WITH DIAERESIS]
			case 0x168: // Ũ	[LATIN CAPITAL LETTER U WITH TILDE]
			case 0x16A: // Ū	[LATIN CAPITAL LETTER U WITH MACRON]
			case 0x16C: // Ŭ	[LATIN CAPITAL LETTER U WITH BREVE]
			case 0x16E: // Ů	[LATIN CAPITAL LETTER U WITH RING ABOVE]
			case 0x170: // Ű	[LATIN CAPITAL LETTER U WITH DOUBLE ACUTE]
			case 0x172: // Ų	[LATIN CAPITAL LETTER U WITH OGONEK]
			case 0x1AF: // Ư	[LATIN CAPITAL LETTER U WITH HORN]
			case 0x1D3: // Ǔ	[LATIN CAPITAL LETTER U WITH CARON]
			case 0x1D5: // Ǖ	[LATIN CAPITAL LETTER U WITH DIAERESIS AND MACRON]
			case 0x1D7: // Ǘ	[LATIN CAPITAL LETTER U WITH DIAERESIS AND ACUTE]
			case 0x1D9: // Ǚ	[LATIN CAPITAL LETTER U WITH DIAERESIS AND CARON]
			case 0x1DB: // Ǜ	[LATIN CAPITAL LETTER U WITH DIAERESIS AND GRAVE]
			case 0x214: // Ȕ	[LATIN CAPITAL LETTER U WITH DOUBLE GRAVE]
			case 0x216: // Ȗ	[LATIN CAPITAL LETTER U WITH INVERTED BREVE]
			case 0x244: // Ʉ	[LATIN CAPITAL LETTER U BAR]
			case 0x1D1C: // ᴜ	[LATIN LETTER SMALL CAPITAL U]
			case 0x1D7E: // ᵾ	[LATIN SMALL CAPITAL LETTER U WITH STROKE]
			case 0x1E72: // Ṳ	[LATIN CAPITAL LETTER U WITH DIAERESIS BELOW]
			case 0x1E74: // Ṵ	[LATIN CAPITAL LETTER U WITH TILDE BELOW]
			case 0x1E76: // Ṷ	[LATIN CAPITAL LETTER U WITH CIRCUMFLEX BELOW]
			case 0x1E78: // Ṹ	[LATIN CAPITAL LETTER U WITH TILDE AND ACUTE]
			case 0x1E7A: // Ṻ	[LATIN CAPITAL LETTER U WITH MACRON AND DIAERESIS]
			case 0x1EE4: // Ụ	[LATIN CAPITAL LETTER U WITH DOT BELOW]
			case 0x1EE6: // Ủ	[LATIN CAPITAL LETTER U WITH HOOK ABOVE]
			case 0x1EE8: // Ứ	[LATIN CAPITAL LETTER U WITH HORN AND ACUTE]
			case 0x1EEA: // Ừ	[LATIN CAPITAL LETTER U WITH HORN AND GRAVE]
			case 0x1EEC: // Ử	[LATIN CAPITAL LETTER U WITH HORN AND HOOK ABOVE]
			case 0x1EEE: // Ữ	[LATIN CAPITAL LETTER U WITH HORN AND TILDE]
			case 0x1EF0: // Ự	[LATIN CAPITAL LETTER U WITH HORN AND DOT BELOW]
			case 0x24CA: // Ⓤ	[CIRCLED LATIN CAPITAL LETTER U]
			case 0xFF35: // Ｕ	[FULLWIDTH LATIN CAPITAL LETTER U]
				outString += "U";
				break;
			case 0xF9: // ù	[LATIN SMALL LETTER U WITH GRAVE]
			case 0xFA: // ú	[LATIN SMALL LETTER U WITH ACUTE]
			case 0xFB: // û	[LATIN SMALL LETTER U WITH CIRCUMFLEX]
			case 0xFC: // ü	[LATIN SMALL LETTER U WITH DIAERESIS]
			case 0x169: // ũ	[LATIN SMALL LETTER U WITH TILDE]
			case 0x16B: // ū	[LATIN SMALL LETTER U WITH MACRON]
			case 0x16D: // ŭ	[LATIN SMALL LETTER U WITH BREVE]
			case 0x16F: // ů	[LATIN SMALL LETTER U WITH RING ABOVE]
			case 0x171: // ű	[LATIN SMALL LETTER U WITH DOUBLE ACUTE]
			case 0x173: // ų	[LATIN SMALL LETTER U WITH OGONEK]
			case 0x1B0: // ư	[LATIN SMALL LETTER U WITH HORN]
			case 0x1D4: // ǔ	[LATIN SMALL LETTER U WITH CARON]
			case 0x1D6: // ǖ	[LATIN SMALL LETTER U WITH DIAERESIS AND MACRON]
			case 0x1D8: // ǘ	[LATIN SMALL LETTER U WITH DIAERESIS AND ACUTE]
			case 0x1DA: // ǚ	[LATIN SMALL LETTER U WITH DIAERESIS AND CARON]
			case 0x1DC: // ǜ	[LATIN SMALL LETTER U WITH DIAERESIS AND GRAVE]
			case 0x215: // ȕ	[LATIN SMALL LETTER U WITH DOUBLE GRAVE]
			case 0x217: // ȗ	[LATIN SMALL LETTER U WITH INVERTED BREVE]
			case 0x289: // ʉ	[LATIN SMALL LETTER U BAR]
			case 0x1D64: // ᵤ	[LATIN SUBSCRIPT SMALL LETTER U]
			case 0x1D99: // ᶙ	[LATIN SMALL LETTER U WITH RETROFLEX HOOK]
			case 0x1E73: // ṳ	[LATIN SMALL LETTER U WITH DIAERESIS BELOW]
			case 0x1E75: // ṵ	[LATIN SMALL LETTER U WITH TILDE BELOW]
			case 0x1E77: // ṷ	[LATIN SMALL LETTER U WITH CIRCUMFLEX BELOW]
			case 0x1E79: // ṹ	[LATIN SMALL LETTER U WITH TILDE AND ACUTE]
			case 0x1E7B: // ṻ	[LATIN SMALL LETTER U WITH MACRON AND DIAERESIS]
			case 0x1EE5: // ụ	[LATIN SMALL LETTER U WITH DOT BELOW]
			case 0x1EE7: // ủ	[LATIN SMALL LETTER U WITH HOOK ABOVE]
			case 0x1EE9: // ứ	[LATIN SMALL LETTER U WITH HORN AND ACUTE]
			case 0x1EEB: // ừ	[LATIN SMALL LETTER U WITH HORN AND GRAVE]
			case 0x1EED: // ử	[LATIN SMALL LETTER U WITH HORN AND HOOK ABOVE]
			case 0x1EEF: // ữ	[LATIN SMALL LETTER U WITH HORN AND TILDE]
			case 0x1EF1: // ự	[LATIN SMALL LETTER U WITH HORN AND DOT BELOW]
			case 0x24E4: // ⓤ	[CIRCLED LATIN SMALL LETTER U]
			case 0xFF55: // ｕ	[FULLWIDTH LATIN SMALL LETTER U]
				outString += "u";
				break;
			case 0x24B0: // ⒰	[PARENTHESIZED LATIN SMALL LETTER U]
				outString += "(";
				outString += "u";
				outString += ")";
				break;
			case 0x1D6B: // ᵫ	[LATIN SMALL LETTER UE]
				outString += "u";
				outString += "e";
				break;
			case 0x1B2: // Ʋ	[LATIN CAPITAL LETTER V WITH HOOK]
			case 0x245: // Ʌ	[LATIN CAPITAL LETTER TURNED V]
			case 0x1D20: // ᴠ	[LATIN LETTER SMALL CAPITAL V]
			case 0x1E7C: // Ṽ	[LATIN CAPITAL LETTER V WITH TILDE]
			case 0x1E7E: // Ṿ	[LATIN CAPITAL LETTER V WITH DOT BELOW]
			case 0x1EFC: // Ỽ	[LATIN CAPITAL LETTER MIDDLE-WELSH V]
			case 0x24CB: // Ⓥ	[CIRCLED LATIN CAPITAL LETTER V]
			case 0xA75E: // Ꝟ	[LATIN CAPITAL LETTER V WITH DIAGONAL STROKE]
			case 0xA768: // Ꝩ	[LATIN CAPITAL LETTER VEND]
			case 0xFF36: // Ｖ	[FULLWIDTH LATIN CAPITAL LETTER V]
				outString += "V";
				break;
			case 0x28B: // ʋ	[LATIN SMALL LETTER V WITH HOOK]
			case 0x28C: // ʌ	[LATIN SMALL LETTER TURNED V]
			case 0x1D65: // ᵥ	[LATIN SUBSCRIPT SMALL LETTER V]
			case 0x1D8C: // ᶌ	[LATIN SMALL LETTER V WITH PALATAL HOOK]
			case 0x1E7D: // ṽ	[LATIN SMALL LETTER V WITH TILDE]
			case 0x1E7F: // ṿ	[LATIN SMALL LETTER V WITH DOT BELOW]
			case 0x24E5: // ⓥ	[CIRCLED LATIN SMALL LETTER V]
			case 0x2C71: // ⱱ	[LATIN SMALL LETTER V WITH RIGHT HOOK]
			case 0x2C74: // ⱴ	[LATIN SMALL LETTER V WITH CURL]
			case 0xA75F: // ꝟ	[LATIN SMALL LETTER V WITH DIAGONAL STROKE]
			case 0xFF56: // ｖ	[FULLWIDTH LATIN SMALL LETTER V]
				outString += "v";
				break;
			case 0xA760: // Ꝡ	[LATIN CAPITAL LETTER VY]
				outString += "V";
				outString += "Y";
				break;
			case 0x24B1: // ⒱	[PARENTHESIZED LATIN SMALL LETTER V]
				outString += "(";
				outString += "v";
				outString += ")";
				break;
			case 0xA761: // ꝡ	[LATIN SMALL LETTER VY]
				outString += "v";
				outString += "y";
				break;
			case 0x174: // Ŵ	[LATIN CAPITAL LETTER W WITH CIRCUMFLEX]
			case 0x1F7: // Ƿ	http;//en.wikipedia.org/wiki/Wynn	[LATIN CAPITAL LETTER WYNN]
			case 0x1D21: // ᴡ	[LATIN LETTER SMALL CAPITAL W]
			case 0x1E80: // Ẁ	[LATIN CAPITAL LETTER W WITH GRAVE]
			case 0x1E82: // Ẃ	[LATIN CAPITAL LETTER W WITH ACUTE]
			case 0x1E84: // Ẅ	[LATIN CAPITAL LETTER W WITH DIAERESIS]
			case 0x1E86: // Ẇ	[LATIN CAPITAL LETTER W WITH DOT ABOVE]
			case 0x1E88: // Ẉ	[LATIN CAPITAL LETTER W WITH DOT BELOW]
			case 0x24CC: // Ⓦ	[CIRCLED LATIN CAPITAL LETTER W]
			case 0x2C72: // Ⱳ	[LATIN CAPITAL LETTER W WITH HOOK]
			case 0xFF37: // Ｗ	[FULLWIDTH LATIN CAPITAL LETTER W]
				outString += "W";
				break;
			case 0x175: // ŵ	[LATIN SMALL LETTER W WITH CIRCUMFLEX]
			case 0x1BF: // ƿ	http;//en.wikipedia.org/wiki/Wynn	[LATIN LETTER WYNN]
			case 0x28D: // ʍ	[LATIN SMALL LETTER TURNED W]
			case 0x1E81: // ẁ	[LATIN SMALL LETTER W WITH GRAVE]
			case 0x1E83: // ẃ	[LATIN SMALL LETTER W WITH ACUTE]
			case 0x1E85: // ẅ	[LATIN SMALL LETTER W WITH DIAERESIS]
			case 0x1E87: // ẇ	[LATIN SMALL LETTER W WITH DOT ABOVE]
			case 0x1E89: // ẉ	[LATIN SMALL LETTER W WITH DOT BELOW]
			case 0x1E98: // ẘ	[LATIN SMALL LETTER W WITH RING ABOVE]
			case 0x24E6: // ⓦ	[CIRCLED LATIN SMALL LETTER W]
			case 0x2C73: // ⱳ	[LATIN SMALL LETTER W WITH HOOK]
			case 0xFF57: // ｗ	[FULLWIDTH LATIN SMALL LETTER W]
				outString += "w";
				break;
			case 0x24B2: // ⒲	[PARENTHESIZED LATIN SMALL LETTER W]
				outString += "(";
				outString += "w";
				outString += ")";
				break;
			case 0x1E8A: // Ẋ	[LATIN CAPITAL LETTER X WITH DOT ABOVE]
			case 0x1E8C: // Ẍ	[LATIN CAPITAL LETTER X WITH DIAERESIS]
			case 0x24CD: // Ⓧ	[CIRCLED LATIN CAPITAL LETTER X]
			case 0xFF38: // Ｘ	[FULLWIDTH LATIN CAPITAL LETTER X]
				outString += "X";
				break;
			case 0x1D8D: // ᶍ	[LATIN SMALL LETTER X WITH PALATAL HOOK]
			case 0x1E8B: // ẋ	[LATIN SMALL LETTER X WITH DOT ABOVE]
			case 0x1E8D: // ẍ	[LATIN SMALL LETTER X WITH DIAERESIS]
			case 0x2093: // ₓ	[LATIN SUBSCRIPT SMALL LETTER X]
			case 0x24E7: // ⓧ	[CIRCLED LATIN SMALL LETTER X]
			case 0xFF58: // ｘ	[FULLWIDTH LATIN SMALL LETTER X]
				outString += "x";
				break;
			case 0x24B3: // ⒳	[PARENTHESIZED LATIN SMALL LETTER X]
				outString += "(";
				outString += "x";
				outString += ")";
				break;
			case 0xDD: // Ý	[LATIN CAPITAL LETTER Y WITH ACUTE]
			case 0x176: // Ŷ	[LATIN CAPITAL LETTER Y WITH CIRCUMFLEX]
			case 0x178: // Ÿ	[LATIN CAPITAL LETTER Y WITH DIAERESIS]
			case 0x1B3: // Ƴ	[LATIN CAPITAL LETTER Y WITH HOOK]
			case 0x232: // Ȳ	[LATIN CAPITAL LETTER Y WITH MACRON]
			case 0x24E: // Ɏ	[LATIN CAPITAL LETTER Y WITH STROKE]
			case 0x28F: // ʏ	[LATIN LETTER SMALL CAPITAL Y]
			case 0x1E8E: // Ẏ	[LATIN CAPITAL LETTER Y WITH DOT ABOVE]
			case 0x1EF2: // Ỳ	[LATIN CAPITAL LETTER Y WITH GRAVE]
			case 0x1EF4: // Ỵ	[LATIN CAPITAL LETTER Y WITH DOT BELOW]
			case 0x1EF6: // Ỷ	[LATIN CAPITAL LETTER Y WITH HOOK ABOVE]
			case 0x1EF8: // Ỹ	[LATIN CAPITAL LETTER Y WITH TILDE]
			case 0x1EFE: // Ỿ	[LATIN CAPITAL LETTER Y WITH LOOP]
			case 0x24CE: // Ⓨ	[CIRCLED LATIN CAPITAL LETTER Y]
			case 0xFF39: // Ｙ	[FULLWIDTH LATIN CAPITAL LETTER Y]
				outString += "Y";
				break;
			case 0xFD: // ý	[LATIN SMALL LETTER Y WITH ACUTE]
			case 0xFF: // ÿ	[LATIN SMALL LETTER Y WITH DIAERESIS]
			case 0x177: // ŷ	[LATIN SMALL LETTER Y WITH CIRCUMFLEX]
			case 0x1B4: // ƴ	[LATIN SMALL LETTER Y WITH HOOK]
			case 0x233: // ȳ	[LATIN SMALL LETTER Y WITH MACRON]
			case 0x24F: // ɏ	[LATIN SMALL LETTER Y WITH STROKE]
			case 0x28E: // ʎ	[LATIN SMALL LETTER TURNED Y]
			case 0x1E8F: // ẏ	[LATIN SMALL LETTER Y WITH DOT ABOVE]
			case 0x1E99: // ẙ	[LATIN SMALL LETTER Y WITH RING ABOVE]
			case 0x1EF3: // ỳ	[LATIN SMALL LETTER Y WITH GRAVE]
			case 0x1EF5: // ỵ	[LATIN SMALL LETTER Y WITH DOT BELOW]
			case 0x1EF7: // ỷ	[LATIN SMALL LETTER Y WITH HOOK ABOVE]
			case 0x1EF9: // ỹ	[LATIN SMALL LETTER Y WITH TILDE]
			case 0x1EFF: // ỿ	[LATIN SMALL LETTER Y WITH LOOP]
			case 0x24E8: // ⓨ	[CIRCLED LATIN SMALL LETTER Y]
			case 0xFF59: // ｙ	[FULLWIDTH LATIN SMALL LETTER Y]
				outString += "y";
				break;
			case 0x24B4: // ⒴	[PARENTHESIZED LATIN SMALL LETTER Y]
				outString += "(";
				outString += "y";
				outString += ")";
				break;
			case 0x179: // Ź	[LATIN CAPITAL LETTER Z WITH ACUTE]
			case 0x17B: // Ż	[LATIN CAPITAL LETTER Z WITH DOT ABOVE]
			case 0x17D: // Ž	[LATIN CAPITAL LETTER Z WITH CARON]
			case 0x1B5: // Ƶ	[LATIN CAPITAL LETTER Z WITH STROKE]
			case 0x21C: // Ȝ	http;//en.wikipedia.org/wiki/Yogh	[LATIN CAPITAL LETTER YOGH]
			case 0x224: // Ȥ	[LATIN CAPITAL LETTER Z WITH HOOK]
			case 0x1D22: // ᴢ	[LATIN LETTER SMALL CAPITAL Z]
			case 0x1E90: // Ẑ	[LATIN CAPITAL LETTER Z WITH CIRCUMFLEX]
			case 0x1E92: // Ẓ	[LATIN CAPITAL LETTER Z WITH DOT BELOW]
			case 0x1E94: // Ẕ	[LATIN CAPITAL LETTER Z WITH LINE BELOW]
			case 0x24CF: // Ⓩ	[CIRCLED LATIN CAPITAL LETTER Z]
			case 0x2C6B: // Ⱬ	[LATIN CAPITAL LETTER Z WITH DESCENDER]
			case 0xA762: // Ꝣ	[LATIN CAPITAL LETTER VISIGOTHIC Z]
			case 0xFF3A: // Ｚ	[FULLWIDTH LATIN CAPITAL LETTER Z]
				outString += "Z";
				break;
			case 0x17A: // ź	[LATIN SMALL LETTER Z WITH ACUTE]
			case 0x17C: // ż	[LATIN SMALL LETTER Z WITH DOT ABOVE]
			case 0x17E: // ž	[LATIN SMALL LETTER Z WITH CARON]
			case 0x1B6: // ƶ	[LATIN SMALL LETTER Z WITH STROKE]
			case 0x21D: // ȝ	http;//en.wikipedia.org/wiki/Yogh	[LATIN SMALL LETTER YOGH]
			case 0x225: // ȥ	[LATIN SMALL LETTER Z WITH HOOK]
			case 0x240: // ɀ	[LATIN SMALL LETTER Z WITH SWASH TAIL]
			case 0x290: // ʐ	[LATIN SMALL LETTER Z WITH RETROFLEX HOOK]
			case 0x291: // ʑ	[LATIN SMALL LETTER Z WITH CURL]
			case 0x1D76: // ᵶ	[LATIN SMALL LETTER Z WITH MIDDLE TILDE]
			case 0x1D8E: // ᶎ	[LATIN SMALL LETTER Z WITH PALATAL HOOK]
			case 0x1E91: // ẑ	[LATIN SMALL LETTER Z WITH CIRCUMFLEX]
			case 0x1E93: // ẓ	[LATIN SMALL LETTER Z WITH DOT BELOW]
			case 0x1E95: // ẕ	[LATIN SMALL LETTER Z WITH LINE BELOW]
			case 0x24E9: // ⓩ	[CIRCLED LATIN SMALL LETTER Z]
			case 0x2C6C: // ⱬ	[LATIN SMALL LETTER Z WITH DESCENDER]
			case 0xA763: // ꝣ	[LATIN SMALL LETTER VISIGOTHIC Z]
			case 0xFF5A: // ｚ	[FULLWIDTH LATIN SMALL LETTER Z]
				outString += "z";
				break;
			case 0x24B5: // ⒵	[PARENTHESIZED LATIN SMALL LETTER Z]
				outString += "(";
				outString += "z";
				outString += ")";
				break;
			case 0x2070: // ⁰	[SUPERSCRIPT ZERO]
			case 0x2080: // ₀	[SUBSCRIPT ZERO]
			case 0x24EA: // ⓪	[CIRCLED DIGIT ZERO]
			case 0x24FF: // ⓿	[NEGATIVE CIRCLED DIGIT ZERO]
			case 0xFF10: // ０	[FULLWIDTH DIGIT ZERO]
				outString += "0";
				break;
			case 0xB9: // ¹	[SUPERSCRIPT ONE]
			case 0x2081: // ₁	[SUBSCRIPT ONE]
			case 0x2460: // ①	[CIRCLED DIGIT ONE]
			case 0x24F5: // ⓵	[DOUBLE CIRCLED DIGIT ONE]
			case 0x2776: // ❶	[DINGBAT NEGATIVE CIRCLED DIGIT ONE]
			case 0x2780: // ➀	[DINGBAT CIRCLED SANS-SERIF DIGIT ONE]
			case 0x278A: // ➊	[DINGBAT NEGATIVE CIRCLED SANS-SERIF DIGIT ONE]
			case 0xFF11: // １	[FULLWIDTH DIGIT ONE]
				outString += "1";
				break;
			case 0x2488: // ⒈	[DIGIT ONE FULL STOP]
				outString += "1";
				outString += ".";
				break;
			case 0x2474: // ⑴	[PARENTHESIZED DIGIT ONE]
				outString += "(";
				outString += "1";
				outString += ")";
				break;
			case 0xB2: // ²	[SUPERSCRIPT TWO]
			case 0x2082: // ₂	[SUBSCRIPT TWO]
			case 0x2461: // ②	[CIRCLED DIGIT TWO]
			case 0x24F6: // ⓶	[DOUBLE CIRCLED DIGIT TWO]
			case 0x2777: // ❷	[DINGBAT NEGATIVE CIRCLED DIGIT TWO]
			case 0x2781: // ➁	[DINGBAT CIRCLED SANS-SERIF DIGIT TWO]
			case 0x278B: // ➋	[DINGBAT NEGATIVE CIRCLED SANS-SERIF DIGIT TWO]
			case 0xFF12: // ２	[FULLWIDTH DIGIT TWO]
				outString += "2";
				break;
			case 0x2489: // ⒉	[DIGIT TWO FULL STOP]
				outString += "2";
				outString += ".";
				break;
			case 0x2475: // ⑵	[PARENTHESIZED DIGIT TWO]
				outString += "(";
				outString += "2";
				outString += ")";
				break;
			case 0xB3: // ³	[SUPERSCRIPT THREE]
			case 0x2083: // ₃	[SUBSCRIPT THREE]
			case 0x2462: // ③	[CIRCLED DIGIT THREE]
			case 0x24F7: // ⓷	[DOUBLE CIRCLED DIGIT THREE]
			case 0x2778: // ❸	[DINGBAT NEGATIVE CIRCLED DIGIT THREE]
			case 0x2782: // ➂	[DINGBAT CIRCLED SANS-SERIF DIGIT THREE]
			case 0x278C: // ➌	[DINGBAT NEGATIVE CIRCLED SANS-SERIF DIGIT THREE]
			case 0xFF13: // ３	[FULLWIDTH DIGIT THREE]
				outString += "3";
				break;
			case 0x248A: // ⒊	[DIGIT THREE FULL STOP]
				outString += "3";
				outString += ".";
				break;
			case 0x2476: // ⑶	[PARENTHESIZED DIGIT THREE]
				outString += "(";
				outString += "3";
				outString += ")";
				break;
			case 0x2074: // ⁴	[SUPERSCRIPT FOUR]
			case 0x2084: // ₄	[SUBSCRIPT FOUR]
			case 0x2463: // ④	[CIRCLED DIGIT FOUR]
			case 0x24F8: // ⓸	[DOUBLE CIRCLED DIGIT FOUR]
			case 0x2779: // ❹	[DINGBAT NEGATIVE CIRCLED DIGIT FOUR]
			case 0x2783: // ➃	[DINGBAT CIRCLED SANS-SERIF DIGIT FOUR]
			case 0x278D: // ➍	[DINGBAT NEGATIVE CIRCLED SANS-SERIF DIGIT FOUR]
			case 0xFF14: // ４	[FULLWIDTH DIGIT FOUR]
				outString += "4";
				break;
			case 0x248B: // ⒋	[DIGIT FOUR FULL STOP]
				outString += "4";
				outString += ".";
				break;
			case 0x2477: // ⑷	[PARENTHESIZED DIGIT FOUR]
				outString += "(";
				outString += "4";
				outString += ")";
				break;
			case 0x2075: // ⁵	[SUPERSCRIPT FIVE]
			case 0x2085: // ₅	[SUBSCRIPT FIVE]
			case 0x2464: // ⑤	[CIRCLED DIGIT FIVE]
			case 0x24F9: // ⓹	[DOUBLE CIRCLED DIGIT FIVE]
			case 0x277A: // ❺	[DINGBAT NEGATIVE CIRCLED DIGIT FIVE]
			case 0x2784: // ➄	[DINGBAT CIRCLED SANS-SERIF DIGIT FIVE]
			case 0x278E: // ➎	[DINGBAT NEGATIVE CIRCLED SANS-SERIF DIGIT FIVE]
			case 0xFF15: // ５	[FULLWIDTH DIGIT FIVE]
				outString += "5";
				break;
			case 0x248C: // ⒌	[DIGIT FIVE FULL STOP]
				outString += "5";
				outString += ".";
				break;
			case 0x2478: // ⑸	[PARENTHESIZED DIGIT FIVE]
				outString += "(";
				outString += "5";
				outString += ")";
				break;
			case 0x2076: // ⁶	[SUPERSCRIPT SIX]
			case 0x2086: // ₆	[SUBSCRIPT SIX]
			case 0x2465: // ⑥	[CIRCLED DIGIT SIX]
			case 0x24FA: // ⓺	[DOUBLE CIRCLED DIGIT SIX]
			case 0x277B: // ❻	[DINGBAT NEGATIVE CIRCLED DIGIT SIX]
			case 0x2785: // ➅	[DINGBAT CIRCLED SANS-SERIF DIGIT SIX]
			case 0x278F: // ➏	[DINGBAT NEGATIVE CIRCLED SANS-SERIF DIGIT SIX]
			case 0xFF16: // ６	[FULLWIDTH DIGIT SIX]
				outString += "6";
				break;
			case 0x248D: // ⒍	[DIGIT SIX FULL STOP]
				outString += "6";
				outString += ".";
				break;
			case 0x2479: // ⑹	[PARENTHESIZED DIGIT SIX]
				outString += "(";
				outString += "6";
				outString += ")";
				break;
			case 0x2077: // ⁷	[SUPERSCRIPT SEVEN]
			case 0x2087: // ₇	[SUBSCRIPT SEVEN]
			case 0x2466: // ⑦	[CIRCLED DIGIT SEVEN]
			case 0x24FB: // ⓻	[DOUBLE CIRCLED DIGIT SEVEN]
			case 0x277C: // ❼	[DINGBAT NEGATIVE CIRCLED DIGIT SEVEN]
			case 0x2786: // ➆	[DINGBAT CIRCLED SANS-SERIF DIGIT SEVEN]
			case 0x2790: // ➐	[DINGBAT NEGATIVE CIRCLED SANS-SERIF DIGIT SEVEN]
			case 0xFF17: // ７	[FULLWIDTH DIGIT SEVEN]
				outString += "7";
				break;
			case 0x248E: // ⒎	[DIGIT SEVEN FULL STOP]
				outString += "7";
				outString += ".";
				break;
			case 0x247A: // ⑺	[PARENTHESIZED DIGIT SEVEN]
				outString += "(";
				outString += "7";
				outString += ")";
				break;
			case 0x2078: // ⁸	[SUPERSCRIPT EIGHT]
			case 0x2088: // ₈	[SUBSCRIPT EIGHT]
			case 0x2467: // ⑧	[CIRCLED DIGIT EIGHT]
			case 0x24FC: // ⓼	[DOUBLE CIRCLED DIGIT EIGHT]
			case 0x277D: // ❽	[DINGBAT NEGATIVE CIRCLED DIGIT EIGHT]
			case 0x2787: // ➇	[DINGBAT CIRCLED SANS-SERIF DIGIT EIGHT]
			case 0x2791: // ➑	[DINGBAT NEGATIVE CIRCLED SANS-SERIF DIGIT EIGHT]
			case 0xFF18: // ８	[FULLWIDTH DIGIT EIGHT]
				outString += "8";
				break;
			case 0x248F: // ⒏	[DIGIT EIGHT FULL STOP]
				outString += "8";
				outString += ".";
				break;
			case 0x247B: // ⑻	[PARENTHESIZED DIGIT EIGHT]
				outString += "(";
				outString += "8";
				outString += ")";
				break;
			case 0x2079: // ⁹	[SUPERSCRIPT NINE]
			case 0x2089: // ₉	[SUBSCRIPT NINE]
			case 0x2468: // ⑨	[CIRCLED DIGIT NINE]
			case 0x24FD: // ⓽	[DOUBLE CIRCLED DIGIT NINE]
			case 0x277E: // ❾	[DINGBAT NEGATIVE CIRCLED DIGIT NINE]
			case 0x2788: // ➈	[DINGBAT CIRCLED SANS-SERIF DIGIT NINE]
			case 0x2792: // ➒	[DINGBAT NEGATIVE CIRCLED SANS-SERIF DIGIT NINE]
			case 0xFF19: // ９	[FULLWIDTH DIGIT NINE]
				outString += "9";
				break;
			case 0x2490: // ⒐	[DIGIT NINE FULL STOP]
				outString += "9";
				outString += ".";
				break;
			case 0x247C: // ⑼	[PARENTHESIZED DIGIT NINE]
				outString += "(";
				outString += "9";
				outString += ")";
				break;
			case 0x2469: // ⑩	[CIRCLED NUMBER TEN]
			case 0x24FE: // ⓾	[DOUBLE CIRCLED NUMBER TEN]
			case 0x277F: // ❿	[DINGBAT NEGATIVE CIRCLED NUMBER TEN]
			case 0x2789: // ➉	[DINGBAT CIRCLED SANS-SERIF NUMBER TEN]
			case 0x2793: // ➓	[DINGBAT NEGATIVE CIRCLED SANS-SERIF NUMBER TEN]
				outString += "1";
				outString += "0";
				break;
			case 0x2491: // ⒑	[NUMBER TEN FULL STOP]
				outString += "1";
				outString += "0";
				outString += ".";
				break;
			case 0x247D: // ⑽	[PARENTHESIZED NUMBER TEN]
				outString += "(";
				outString += "1";
				outString += "0";
				outString += ")";
				break;
			case 0x246A: // ⑪	[CIRCLED NUMBER ELEVEN]
			case 0x24EB: // ⓫	[NEGATIVE CIRCLED NUMBER ELEVEN]
				outString += "1";
				outString += "1";
				break;
			case 0x2492: // ⒒	[NUMBER ELEVEN FULL STOP]
				outString += "1";
				outString += "1";
				outString += ".";
				break;
			case 0x247E: // ⑾	[PARENTHESIZED NUMBER ELEVEN]
				outString += "(";
				outString += "1";
				outString += "1";
				outString += ")";
				break;
			case 0x246B: // ⑫	[CIRCLED NUMBER TWELVE]
			case 0x24EC: // ⓬	[NEGATIVE CIRCLED NUMBER TWELVE]
				outString += "1";
				outString += "2";
				break;
			case 0x2493: // ⒓	[NUMBER TWELVE FULL STOP]
				outString += "1";
				outString += "2";
				outString += ".";
				break;
			case 0x247F: // ⑿	[PARENTHESIZED NUMBER TWELVE]
				outString += "(";
				outString += "1";
				outString += "2";
				outString += ")";
				break;
			case 0x246C: // ⑬	[CIRCLED NUMBER THIRTEEN]
			case 0x24ED: // ⓭	[NEGATIVE CIRCLED NUMBER THIRTEEN]
				outString += "1";
				outString += "3";
				break;
			case 0x2494: // ⒔	[NUMBER THIRTEEN FULL STOP]
				outString += "1";
				outString += "3";
				outString += ".";
				break;
			case 0x2480: // ⒀	[PARENTHESIZED NUMBER THIRTEEN]
				outString += "(";
				outString += "1";
				outString += "3";
				outString += ")";
				break;
			case 0x246D: // ⑭	[CIRCLED NUMBER FOURTEEN]
			case 0x24EE: // ⓮	[NEGATIVE CIRCLED NUMBER FOURTEEN]
				outString += "1";
				outString += "4";
				break;
			case 0x2495: // ⒕	[NUMBER FOURTEEN FULL STOP]
				outString += "1";
				outString += "4";
				outString += ".";
				break;
			case 0x2481: // ⒁	[PARENTHESIZED NUMBER FOURTEEN]
				outString += "(";
				outString += "1";
				outString += "4";
				outString += ")";
				break;
			case 0x246E: // ⑮	[CIRCLED NUMBER FIFTEEN]
			case 0x24EF: // ⓯	[NEGATIVE CIRCLED NUMBER FIFTEEN]
				outString += "1";
				outString += "5";
				break;
			case 0x2496: // ⒖	[NUMBER FIFTEEN FULL STOP]
				outString += "1";
				outString += "5";
				outString += ".";
				break;
			case 0x2482: // ⒂	[PARENTHESIZED NUMBER FIFTEEN]
				outString += "(";
				outString += "1";
				outString += "5";
				outString += ")";
				break;
			case 0x246F: // ⑯	[CIRCLED NUMBER SIXTEEN]
			case 0x24F0: // ⓰	[NEGATIVE CIRCLED NUMBER SIXTEEN]
				outString += "1";
				outString += "6";
				break;
			case 0x2497: // ⒗	[NUMBER SIXTEEN FULL STOP]
				outString += "1";
				outString += "6";
				outString += ".";
				break;
			case 0x2483: // ⒃	[PARENTHESIZED NUMBER SIXTEEN]
				outString += "(";
				outString += "1";
				outString += "6";
				outString += ")";
				break;
			case 0x2470: // ⑰	[CIRCLED NUMBER SEVENTEEN]
			case 0x24F1: // ⓱	[NEGATIVE CIRCLED NUMBER SEVENTEEN]
				outString += "1";
				outString += "7";
				break;
			case 0x2498: // ⒘	[NUMBER SEVENTEEN FULL STOP]
				outString += "1";
				outString += "7";
				outString += ".";
				break;
			case 0x2484: // ⒄	[PARENTHESIZED NUMBER SEVENTEEN]
				outString += "(";
				outString += "1";
				outString += "7";
				outString += ")";
				break;
			case 0x2471: // ⑱	[CIRCLED NUMBER EIGHTEEN]
			case 0x24F2: // ⓲	[NEGATIVE CIRCLED NUMBER EIGHTEEN]
				outString += "1";
				outString += "8";
				break;
			case 0x2499: // ⒙	[NUMBER EIGHTEEN FULL STOP]
				outString += "1";
				outString += "8";
				outString += ".";
				break;
			case 0x2485: // ⒅	[PARENTHESIZED NUMBER EIGHTEEN]
				outString += "(";
				outString += "1";
				outString += "8";
				outString += ")";
				break;
			case 0x2472: // ⑲	[CIRCLED NUMBER NINETEEN]
			case 0x24F3: // ⓳	[NEGATIVE CIRCLED NUMBER NINETEEN]
				outString += "1";
				outString += "9";
				break;
			case 0x249A: // ⒚	[NUMBER NINETEEN FULL STOP]
				outString += "1";
				outString += "9";
				outString += ".";
				break;
			case 0x2486: // ⒆	[PARENTHESIZED NUMBER NINETEEN]
				outString += "(";
				outString += "1";
				outString += "9";
				outString += ")";
				break;
			case 0x2473: // ⑳	[CIRCLED NUMBER TWENTY]
			case 0x24F4: // ⓴	[NEGATIVE CIRCLED NUMBER TWENTY]
				outString += "2";
				outString += "0";
				break;
			case 0x249B: // ⒛	[NUMBER TWENTY FULL STOP]
				outString += "2";
				outString += "0";
				outString += ".";
				break;
			case 0x2487: // ⒇	[PARENTHESIZED NUMBER TWENTY]
				outString += "(";
				outString += "2";
				outString += "0";
				outString += ")";
				break;
			case 0xAB: // «	[LEFT-POINTING DOUBLE ANGLE QUOTATION MARK]
			case 0xBB: // »	[RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK]
			case 0x201C: // “	[LEFT DOUBLE QUOTATION MARK]
			case 0x201D: // ”	[RIGHT DOUBLE QUOTATION MARK]
			case 0x201E: // „	[DOUBLE LOW-9 QUOTATION MARK]
			case 0x2033: // ″	[DOUBLE PRIME]
			case 0x2036: // ‶	[REVERSED DOUBLE PRIME]
			case 0x275D: // ❝	[HEAVY DOUBLE TURNED COMMA QUOTATION MARK ORNAMENT]
			case 0x275E: // ❞	[HEAVY DOUBLE COMMA QUOTATION MARK ORNAMENT]
			case 0x276E: // ❮	[HEAVY LEFT-POINTING ANGLE QUOTATION MARK ORNAMENT]
			case 0x276F: // ❯	[HEAVY RIGHT-POINTING ANGLE QUOTATION MARK ORNAMENT]
			case 0xFF02: // ＂	[FULLWIDTH QUOTATION MARK]
				outString += "\"";
				break;
			case 0x2018: // ‘	[LEFT SINGLE QUOTATION MARK]
			case 0x2019: // ’	[RIGHT SINGLE QUOTATION MARK]
			case 0x201A: // ‚	[SINGLE LOW-9 QUOTATION MARK]
			case 0x201B: // ‛	[SINGLE HIGH-REVERSED-9 QUOTATION MARK]
			case 0x2032: // ′	[PRIME]
			case 0x2035: // ‵	[REVERSED PRIME]
			case 0x2039: // ‹	[SINGLE LEFT-POINTING ANGLE QUOTATION MARK]
			case 0x203A: // ›	[SINGLE RIGHT-POINTING ANGLE QUOTATION MARK]
			case 0x275B: // ❛	[HEAVY SINGLE TURNED COMMA QUOTATION MARK ORNAMENT]
			case 0x275C: // ❜	[HEAVY SINGLE COMMA QUOTATION MARK ORNAMENT]
			case 0xFF07: // ＇	[FULLWIDTH APOSTROPHE]
				outString += "'";
				break;
			case 0x2010: // ‐	[HYPHEN]
			case 0x2011: // ‑	[NON-BREAKING HYPHEN]
			case 0x2012: // ‒	[FIGURE DASH]
			case 0x2013: // –	[EN DASH]
			case 0x2014: // —	[EM DASH]
			case 0x207B: // ⁻	[SUPERSCRIPT MINUS]
			case 0x208B: // ₋	[SUBSCRIPT MINUS]
			case 0xFF0D: // －	[FULLWIDTH HYPHEN-MINUS]
				outString += "-";
				break;
			case 0x2045: // ⁅	[LEFT SQUARE BRACKET WITH QUILL]
			case 0x2772: // ❲	[LIGHT LEFT TORTOISE SHELL BRACKET ORNAMENT]
			case 0xFF3B: // ［	[FULLWIDTH LEFT SQUARE BRACKET]
				outString += "[";
				break;
			case 0x2046: // ⁆	[RIGHT SQUARE BRACKET WITH QUILL]
			case 0x2773: // ❳	[LIGHT RIGHT TORTOISE SHELL BRACKET ORNAMENT]
			case 0xFF3D: // ］	[FULLWIDTH RIGHT SQUARE BRACKET]
				outString += "]";
				break;
			case 0x207D: // ⁽	[SUPERSCRIPT LEFT PARENTHESIS]
			case 0x208D: // ₍	[SUBSCRIPT LEFT PARENTHESIS]
			case 0x2768: // ❨	[MEDIUM LEFT PARENTHESIS ORNAMENT]
			case 0x276A: // ❪	[MEDIUM FLATTENED LEFT PARENTHESIS ORNAMENT]
			case 0xFF08: // （	[FULLWIDTH LEFT PARENTHESIS]
				outString += "(";
				break;
			case 0x2E28: // ⸨	[LEFT DOUBLE PARENTHESIS]
				outString += "(";
				outString += "(";
				break;
			case 0x207E: // ⁾	[SUPERSCRIPT RIGHT PARENTHESIS]
			case 0x208E: // ₎	[SUBSCRIPT RIGHT PARENTHESIS]
			case 0x2769: // ❩	[MEDIUM RIGHT PARENTHESIS ORNAMENT]
			case 0x276B: // ❫	[MEDIUM FLATTENED RIGHT PARENTHESIS ORNAMENT]
			case 0xFF09: // ）	[FULLWIDTH RIGHT PARENTHESIS]
				outString += ")";
				break;
			case 0x2E29: // ⸩	[RIGHT DOUBLE PARENTHESIS]
				outString += ")";
				outString += ")";
				break;
			case 0x276C: // ❬	[MEDIUM LEFT-POINTING ANGLE BRACKET ORNAMENT]
			case 0x2770: // ❰	[HEAVY LEFT-POINTING ANGLE BRACKET ORNAMENT]
			case 0xFF1C: // ＜	[FULLWIDTH LESS-THAN SIGN]
				outString += "<";
				break;
			case 0x276D: // ❭	[MEDIUM RIGHT-POINTING ANGLE BRACKET ORNAMENT]
			case 0x2771: // ❱	[HEAVY RIGHT-POINTING ANGLE BRACKET ORNAMENT]
			case 0xFF1E: // ＞	[FULLWIDTH GREATER-THAN SIGN]
				outString += ">";
				break;
			case 0x2774: // ❴	[MEDIUM LEFT CURLY BRACKET ORNAMENT]
			case 0xFF5B: // ｛	[FULLWIDTH LEFT CURLY BRACKET]
				outString += "{";
				break;
			case 0x2775: // ❵	[MEDIUM RIGHT CURLY BRACKET ORNAMENT]
			case 0xFF5D: // ｝	[FULLWIDTH RIGHT CURLY BRACKET]
				outString += "}";
				break;
			case 0x207A: // ⁺	[SUPERSCRIPT PLUS SIGN]
			case 0x208A: // ₊	[SUBSCRIPT PLUS SIGN]
			case 0xFF0B: // ＋	[FULLWIDTH PLUS SIGN]
				outString += "+";
				break;
			case 0x207C: // ⁼	[SUPERSCRIPT EQUALS SIGN]
			case 0x208C: // ₌	[SUBSCRIPT EQUALS SIGN]
			case 0xFF1D: // ＝	[FULLWIDTH EQUALS SIGN]
				outString += "=";
				break;
			case 0xFF01: // ！	[FULLWIDTH EXCLAMATION MARK]
				outString += "!";
				break;
			case 0x203C: // ‼	[DOUBLE EXCLAMATION MARK]
				outString += "!";
				outString += "!";
				break;
			case 0x2049: // ⁉	[EXCLAMATION QUESTION MARK]
				outString += "!";
				outString += "?";
				break;
			case 0xFF03: // ＃	[FULLWIDTH NUMBER SIGN]
				outString += "#";
				break;
			case 0xFF04: // ＄	[FULLWIDTH DOLLAR SIGN]
				outString += "$";
				break;
			case 0x2052: // ⁒	[COMMERCIAL MINUS SIGN]
			case 0xFF05: // ％	[FULLWIDTH PERCENT SIGN]
				outString += "%";
				break;
			case 0xFF06: // ＆	[FULLWIDTH AMPERSAND]
				outString += "&";
				break;
			case 0x204E: // ⁎	[LOW ASTERISK]
			case 0xFF0A: // ＊	[FULLWIDTH ASTERISK]
				outString += "*";
				break;
			case 0xFF0C: // ，	[FULLWIDTH COMMA]
				outString += ",";
				break;
			case 0xFF0E: // ．	[FULLWIDTH FULL STOP]
				outString += ".";
				break;
			case 0x2044: // ⁄	[FRACTION SLASH]
			case 0xFF0F: // ／	[FULLWIDTH SOLIDUS]
				outString += "/";
				break;
			case 0xFF1A: // ：	[FULLWIDTH COLON]
				outString += ":";
				break;
			case 0x204F: // ⁏	[REVERSED SEMICOLON]
			case 0xFF1B: // ；	[FULLWIDTH SEMICOLON]
				outString += ";";
				break;
			case 0xFF1F: // ？	[FULLWIDTH QUESTION MARK]
				outString += "?";
				break;
			case 0x2047: // ⁇	[DOUBLE QUESTION MARK]
				outString += "?";
				outString += "?";
				break;
			case 0x2048: // ⁈	[QUESTION EXCLAMATION MARK]
				outString += "?";
				outString += "!";
				break;
			case 0xFF20: // ＠	[FULLWIDTH COMMERCIAL AT]
				outString += "@";
				break;
			case 0xFF3C: // ＼	[FULLWIDTH REVERSE SOLIDUS]
				outString += "\\";
				break;
			case 0x2038: // ‸	[CARET]
			case 0xFF3E: // ＾	[FULLWIDTH CIRCUMFLEX ACCENT]
				outString += "^";
				break;
			case 0xFF3F: // ＿	[FULLWIDTH LOW LINE]
				outString += "_";
				break;
			case 0x2053: // ⁓	[SWUNG DASH]
			case 0xFF5E: // ～	[FULLWIDTH TILDE]
				outString += "~";
				break;
			default:
				outString += (replaceUnmapped ? defaultString : String.fromCharCode(charCode));
				break;
		}

		return outString;
	};
}());