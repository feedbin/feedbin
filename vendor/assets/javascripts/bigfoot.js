//   _______    ________  _______    ______   ______   ______   _________
// /_______/\  /_______/\/______/\  /_____/\ /_____/\ /_____/\ /________/\
// \::: _  \ \ \__.::._\/\::::__\/__\::::_\/_\:::_ \ \\:::_ \ \\__.::.__\/
//  \::(_)  \/_   \::\ \  \:\ /____/\\:\/___/\\:\ \ \ \\:\ \ \ \  \::\ \
//   \::  _  \ \  _\::\ \__\:\\_  _\/ \:::._\/ \:\ \ \ \\:\ \ \ \  \::\ \
//    \::(_)  \ \/__\::\__/\\:\_\ \ \  \:\ \    \:\_\ \ \\:\_\ \ \  \::\ \
//     \_______\/\________\/ \_____\/   \_\/     \_____\/ \_____\/   \__\/
// 		   _________________________________________________________________
// 		  /________________________________________________________________/\
// 		  \________________________________________________________________\/

// PURPOSE -----
// Looks through the page's markup to identify footnote links/ content.
// It then creates footnote buttons in place of the footnote links and hides the content.
// Finally, creates and positions footnotes when the generated buttons are pressed.

// IN ----------
// An optional object literal specifying script settings.

// OUT ---------
// Returns an object with the following methods:
// close: closes footnotes matching the jQuery selector passed to the function.
// activate: activates the footnote button matching the jQuery selector passed to the function.

// INFO --------
// Developed and maintained by Chris Sauve (http://pxldot.com)
// Documentation, license, and other information can be found at http://cmsauve.com/projects/bigfoot.

// TODO --------
// - Better handling of hover
// - Ability to position/ size popover relative to a containing element (rather than the window)
// - Compensate for zoom position on mobile

// KNOWN ISSUES -
// - Safari 7 doesn't properly calculate the scrollheight of the content wrapper and, as a result, will not
//		properly indicate a scrollable footnote
// - Popovers that are instantiated at a smaller font size which is then resized to a larger one won't adhere
//		to your chosen max-height (in CSS) since JS tries to keep it from running off the top/ bottom of the page
//		but does so using pixel values tied to the sizes of the footnote content when it was originally activated.
//		If anyone has any ideas on this, please let me know!



(function($) {

	$.bigfoot = function(options) {


		//  ______   ______   _________  _________  ________  ___   __    _______    ______
		// /_____/\ /_____/\ /________/\/________/\/_______/\/__/\ /__/\ /______/\  /_____/\
		// \::::_\/_\::::_\/_\__.::.__\/\__.::.__\/\__.::._\/\::\_\\  \ \\::::__\/__\::::_\/_
		//  \:\/___/\\:\/___/\  \::\ \     \::\ \     \::\ \  \:. `-\  \ \\:\ /____/\\:\/___/\
		//   \_::._\:\\::___\/_  \::\ \     \::\ \    _\::\ \__\:. _    \ \\:\\_  _\/ \_::._\:\
		//     /____\:\\:\____/\  \::\ \     \::\ \  /__\::\__/\\. \`-\  \ \\:\_\ \ \   /____\:\
		//     \_____\/ \_____\/   \__\/      \__\/  \________\/ \__\/ \__\/ \_____\/   \_____\/
		//

		var settings = $.extend(
			{
				actionOriginalFN 	: "hide", // "delete", "hide", or "ignore"
				activateOnHover 	: false,
				allowMultipleFN 	: false,
				appendPopoversTo 	: undefined,
				deleteOnUnhover 	: false,
				hoverDelay 			: 250,
				popoverDeleteDelay	: 500,
				popoverCreateDelay	: 100,
				positionNextToBlock : true,
				positionContent 	: true,
				preventPageScroll 	: true,
				scope				: false,

				contentMarkup 		: "<aside class=\"footnote-content bottom\"" +
											"data-footnote-identifier=\"{{FOOTNOTENUM}}\" " +
											"alt=\"Footnote {{FOOTNOTENUM}}\">" +
												"<div class=\"footnote-main-wrapper\">" +
													"<div class=\"footnote-content-wrapper\">" +
														"{{FOOTNOTECONTENT}}" +
												"</div></div>" +
											"<div class=\"tooltip\"></div>" +
										"</aside>",

				buttonMarkup 		:  "<a href=\"#\" class=\"footnote-button\" " +
											"data-footnote-identifier=\"{{FOOTNOTENUM}}\" " +
											"alt=\"See Footnote {{FOOTNOTENUM}}\" " +
											"rel=\"footnote\"" +
											"data-footnote-content=\"{{FOOTNOTECONTENT}}\">" +
												"<span class=\"footnote-circle\" data-footnote-identifier=\"{{FOOTNOTENUM}}\"></span>" +
												"<span class=\"footnote-circle\"></span>" +
												"<span class=\"footnote-circle\"></span>" +
										"</a>"
			}, options);



		//  ________  ___   __     ________  _________
		// /_______/\/__/\ /__/\  /_______/\/________/\
		// \__.::._\/\::\_\\  \ \ \__.::._\/\__.::.__\/
		//    \::\ \  \:. `-\  \ \   \::\ \    \::\ \
		//    _\::\ \__\:. _    \ \  _\::\ \__  \::\ \
		//   /__\::\__/\\. \`-\  \ \/__\::\__/\  \::\ \
		//   \________\/ \__\/ \__\/\________\/   \__\/
		//


		// FUNCTION ----
		// Footnote button/ content initializer (run on doc.ready)

		// PURPOSE -----
		// Finds the likely footnote links and then uses their target to find the content

		var footnoteInit = function() {

			// Get all of the possible footnote links
			var footnoteButtonSearchQuery;
			footnoteButtonSearchQuery = !settings.scope ? "a[href*=\"#\"]" : settings.scope + " a[href*=\"#\"]";

			// Filter down to links that:
			// - have an HREF referencing a footnote, OR
			// - have a rel attribute of footnote
			// AND that aren't a descendant of a footnote (prevents backlinks)
			var $footnoteAnchors = $(footnoteButtonSearchQuery).filter(function() {
				var $this = $(this);
				var relAttr = $this.attr("rel");
				if(!relAttr || relAttr == "null") {
					relAttr = "";
				}
				return ($this.attr("href") + relAttr).match(/(fn|footnote|note)[:\-_\d]/gi) && $this.closest("[class*=footnote]:not(a):not(sup)").length < 1;
			}); // End of footnote link .filter()

			var footnotes 		= [],
				footnoteLinks 	= [],
				finalFNLinks    = [],
				relatedFN,
				$closestFootnoteLi;

			// Resolve issues with superscript/ anchor combination
			cleanFootnoteLinks($footnoteAnchors, footnoteLinks);

			// Get the footnote that the link was pointing to
			$(footnoteLinks).each(function() {
				relatedFN = $(this).attr("data-footnote-ref").replace(":", "\\:");
				$closestFootnoteLi = $(relatedFN).closest("li");
				if($closestFootnoteLi.length > 0) {
					footnotes.push($closestFootnoteLi);
					finalFNLinks.push(this);
				}
			});

			// Initiates the button with the footnote content
			// Also performs the desired action on the original footnotes
			for(var i = 0; i<footnotes.length; i++) {

				// Removes any backlinks and hackily encodes double quotes and >/< symbols to prevent conflicts
				var footnoteContent = removeBackLinks($(footnotes[i]).html().trim(), $(finalFNLinks[i]).data("footnote-backlink-ref"))
										.replace(/"/g, "&quot;").replace(/&lt;/g, "&ltsym;").replace(/&gt;/g, "&gtsym;"),
					$footnoteNum = +(i + 1),
					footnoteButton = "",
					$footnoteButton;

				// Add a paragraph container if the footnote was written directly in the list element
				if(footnoteContent.indexOf("<") !== 0) {
					footnoteContent = "<p>" + footnoteContent + "</p>";
				}

				// Gives default button markup unless custom one is defined
				// Gets the easy replacements out of the way
				footnoteButton = settings.buttonMarkup.replace(/\{\{FOOTNOTENUM\}\}/g, $footnoteNum).replace(/\{\{FOOTNOTECONTENT\}\}/g, footnoteContent);

				// Handles replacements of SUP/FN attribute requests
				footnoteButton = replaceWithReferenceAttributes(footnoteButton, "SUP", $(finalFNLinks[i]));
				footnoteButton = replaceWithReferenceAttributes(footnoteButton, "FN", $(footnotes[i]));

				$footnoteButton = $(footnoteButton).insertAfter($(finalFNLinks[i]));
				$(finalFNLinks[i]).remove();

				var $parent = $(footnotes[i]).parent();
				switch(settings.actionOriginalFN.toLowerCase()) {
					case "delete":
						$(footnotes[i]).remove();
						deleteEmptyOrHR($parent);
						break;
					case "hide":
						$(footnotes[i]).addClass("hidden").css({"display": "none"});
						deleteEmptyOrHR($parent);
						break;
				}
			} // end of loop through footnotes
		}


		// FUNCTION ----
		// cleanFootnoteLinks

		// PURPOSE -----
		// Groups the ID and HREF of a superscript/ anchor tag pair in data attributes
		// This resolves the issue of the href and backlink id being separated between the two elements

		// IN ----------
		// Anchors that link to footnotes

		// OUT ---------
		// Array of top-level emenets with data attributes for combined ID/ HREF

		function cleanFootnoteLinks($footnoteAnchors, footnoteLinks) {
			var $supParent,
				$supChild,
				linkHREF,
				linkID;

			// Problem: backlink ID might point to containing superscript of the fn link
			// Solution: Check if there is a superscript and move the href/ ID up to it.
			// The combined id/ href of the sup/a pair are stored in sup using data attributes
			$footnoteAnchors.each(function() {
				var $this = $(this);
				linkHREF = "#" + ($this.attr("href")).split("#")[1]; // just the fragment ID
				$supParent = $this.closest("sup");
				$supChild = $this.find("sup");

				if($supParent.length > 0) {
					// Assign the link ID to be the parent's and child's combined
					linkID = ($supParent.attr("id") || "") + ($this.attr("id") || "");
					footnoteLinks.push(
						$supParent.attr({
							"data-footnote-backlink-ref": linkID,
							"data-footnote-ref": linkHREF
						})
					);
				} else if($supChild.length > 0) {
					linkID = ($supChild.attr("id") || "") + ($this.attr("id") || "");
					footnoteLinks.push(
						$this.attr({
							"data-footnote-backlink-ref": linkID,
							"data-footnote-ref": linkHREF
						})
					);
				} else {
					// || "" protects against undefined ID's
					linkID = $this.attr("id") || "";
					footnoteLinks.push(
						$this.attr({
							"data-footnote-backlink-ref": linkID,
							"data-footnote-ref": linkHREF
						})
					);
				}
			});
		}


		// FUNCTION ----
		// deleteEmptyOrHR

		// PURPOSE -----
		// Propogates the decision of deleting/ hiding the original footnotes up the hierarchy,
		// eliminating any empty/ fully-hidden elements containing the footnotes and
		// any horizontal rules used to denote the start of the footnote section

		// IN ----------
		// Container of the footnote that was deleted/ hidden

		// OUT ---------
		// Array of top-level emenets with data attributes for combined ID/ HREF

		function deleteEmptyOrHR($el) {
			// If it has no children or all children have been hidden
			if($el.is(":empty") || $el.children(":not(.hidden)").length == 0) {
				var $parent = $el.parent();
				if(settings.actionOriginalFN.toLowerCase() === "delete") {
					$el.remove();
				} else {
					$el.addClass("hidden").css({"display": "none"});
				}

				// Propogate up to the container element
				deleteEmptyOrHR($parent);

			} else if($el.children(":not(.hidden)").length == $el.children("hr:not(.hidden)").length) {

				// If the only child not hidden/ removed is a horizontal rule, remove the entire container
				var $parent = $el.parent();
				if(settings.actionOriginalFN.toLowerCase() === "delete") {
					$el.remove();
				} else {
					$el.children("hr").addClass("hidden").css({"display": "none"});
					$el.addClass("hidden").css({"display": "none"});
				}

				// Propogate up to the container element
				deleteEmptyOrHR($parent);
			}
		}


		// FUNCTION ----
		// removeBackLinks

		// PURPOSE -----
		// Removes any links from the footnote back to the footnote link
		// as these don't make sense when the footnote is shown inline

		// IN ----------
		// HTML of the footnote possibly containing the backlink and
		// the ID(s) of the footnote link

		// OUT ---------
		// New HTML string with relevant links taken out

		function removeBackLinks(footnoteHTML, backlinkID) {

			// First, though, take care of multiple ID's by getting rid of spaces
			if(backlinkID.indexOf(" ") >= 0) {
				backlinkID = backlinkID.trim().replace(/ +/g, "|").replace(/(.*)/g, "($1)");
			}

			// Regex finds the preceding space/ nbsp, the anchor tag and contents
			var regexPat = "(\s|&nbsp;)*<\s*a[^#<]*#" + backlinkID + "[^>]*>(.*?)<\s*/\s*a>";
			var regex = new RegExp(regexPat, "g");
			return footnoteHTML.replace(regex, "").replace("[]", "");
		}


		// FUNCTION ----
		// replaceWithReferenceAttributes

		// PURPOSE -----
		// Replaces the reference attributes (encased in {{}}) with the relevant attributes
		// from the desired element; for example, {{SUP:id}} will be replaced with the ID of the
		// superscript element passed as $referenceElement

		// IN ----------
		// String to do replacements on, the reference keyword to look for (i.e., BUTTON or SUP),
		// and the associated element to search through for the identified attribute(s)

		// OUT ---------
		// New string with replacements performed

		function replaceWithReferenceAttributes(string, referenceKeyword, $referenceElement) {
			var refRegex = new RegExp("\{\{" + referenceKeyword + ":([^\}]*)\}\}", "g"),
				refMatches,
				refReplaceText,
				refReplaceRegex;

			// Performs the regex and does the replacement until it doesn't find any more matches
			while (refMatches = refRegex.exec(string)) {
				// refMatches[1] stores the attribute that is to be matched
				 if(refMatches[1]) {
					refReplaceText = $referenceElement.attr(refMatches[1]) || "";
					string = string.replace("\{\{" + referenceKeyword + ":" + refMatches[1] + "\}\}", refReplaceText);
				}
			}
			return string;
		}



		//  ________   ______  _________  ________  __   __   ________   _________  ______
		// /_______/\ /_____/\/________/\/_______/\/_/\ /_/\ /_______/\ /________/\/_____/\
		// \::: _  \ \\:::__\/\__.::.__\/\__.::._\/\:\ \\ \ \\::: _  \ \\__.::.__\/\::::_\/_
		//  \::(_)  \ \\:\ \  __ \::\ \     \::\ \  \:\ \\ \ \\::(_)  \ \  \::\ \   \:\/___/\
		//   \:: __  \ \\:\ \/_/\ \::\ \    _\::\ \__\:\_/.:\ \\:: __  \ \  \::\ \   \::___\/_
		//    \:.\ \  \ \\:\_\ \ \ \::\ \  /__\::\__/\\ ..::/ / \:.\ \  \ \  \::\ \   \:\____/\
		//     \__\/\__\/ \_____\/  \__\/  \________\/ \___/_(   \__\/\__\/   \__\/    \_____\/
		//


		// FUNCTION ----
		// buttonHover

		// PURPOSE -----
		// To activate the popover of a hovered footnote button
		// Also removes other popovers, if allowMultipleFN is false

		// IN ----------
		// Event that contains the target of the mouseenter event

		var buttonHover = function(e) {
			if(settings.activateOnHover) {
				var $buttonHovered = $(e.target).closest(".footnote-button"),
					dataIdentifier = "[data-footnote-identifier=\"" + $buttonHovered.attr("data-footnote-identifier") + "\"]";
				if($buttonHovered.hasClass("active")) return;

				$buttonHovered.addClass("hover-instantiated");

				// Delete other popovers, unless overriden in the settings
				if(!settings.allowMultipleFN) {
					var otherPopoverSelector = ".footnote-content:not(" + dataIdentifier + ")";
					removePopovers(otherPopoverSelector);
				}
				createPopover(".footnote-button" + dataIdentifier).addClass("hover-instantiated");
			}
		}


		// FUNCTION ----
		// touchClick

		// PURPOSE -----
		// Activates the button the was clicked/ taps
		// Also removes other popovers, if allowMultipleFN is false
		// Finally, removes all popovers if something non-fn related was clicked/ tapped

		// IN ----------
		// Event that contains the target of the tap/click event

		var touchClick = function(e){
			var $target			= $(e.target),
				$nearButton		= $target.closest(".footnote-button");
				$nearFootnote	= $target.closest(".footnote-content");

			// If a button was tapped/ clicked
			if($nearButton.length > 0) {
				// Button was clicked
				// Cancel the link, if it exists
				e.preventDefault();

				// Do the button clicking
				clickButton($nearButton);

			} else if($nearFootnote.length < 1) {
				// Something other than a button or popover was pressed
				if($(".footnote-content").length > 0) {
					removePopovers();
				}

			}
		}


		// FUNCTION ----
		// clickButton

		// PURPOSE -----
		// Handles the logic of clicking/ tapping the footnote button
		// That is, activates the popover if it isn't already active (+ deactivate others, if appropriate)
		// or, deactivates the popover if it is already active

		// IN ----------
		// Button being clicked/ pressed

		var clickButton = function($button) {

			// Cancel blur
			$button.blur();

			// Get the identifier of the footnote
			var dataIdentifier = "data-footnote-identifier=\"" + $button.attr("data-footnote-identifier") + "\"";

			// Only create footnote if it's not already active
			// If it's activating, ignore the new activation until the popover is fully formed.
			if($button.hasClass("changing")) {

				return;

			} else if(!$button.hasClass("active")) {

				$button.addClass("changing");
				setTimeout(function() {
					$button.removeClass("changing");
				}, settings.popoverCreateDelay);
				createPopover(".footnote-button[" + dataIdentifier + "]");
				$button.addClass("click-instantiated");

				// Delete all other footnote popovers if we are only allowing one
				if(!settings.allowMultipleFN) {
					removePopovers(".footnote-content:not([" + dataIdentifier + "])");
				}

			} else {

				// A fully instantiated footnote; either remove it or all footnotes, depending on settings
				if(!settings.allowMultipleFN) {
					removePopovers();
				} else {
					removePopovers(".footnote-content[" + dataIdentifier + "]");
				}

			}
		}


		// FUNCTION ----
		// createPopover

		// PURPOSE -----
		// Instantiates the footnote popover of the buttons matching the passed selector.
		// This includes replacing any variables in the content markup, decoding any special characters,
		// Adding the new element to the page, calling the position function, and adding the scroll handler

		// IN ----------
		// Selector of buttons that are to be activated

		// OUT ---------
		// All footnotes activated by the function

		var createPopover = function(selector) {

			selector = selector || ".footnote-button";

			// Activate all matching if multiple footnotes are allowed
			// Or only the first matching element otherwise
			if(settings.allowMultipleFN) {
				var $buttons = $(selector).closest(".footnote-button");
			} else {
				var $buttons = $(selector + ":first").closest(".footnote-button");
			}

			$buttons.each(function() {
				var $this = $(this);

				try {
					// Gets the easy replacements out of the way (try is there to ignore the "replacing undefined" error if it's activated too freuqnetly)
					var content = settings.contentMarkup
								.replace(/\{\{FOOTNOTENUM\}\}/g, $this.attr("data-footnote-identifier"))
								.replace(/\{\{FOOTNOTECONTENT\}\}/g, $this.attr("data-footnote-content").replace(/&gtsym;/, "&gt;").replace(/&ltsym;/, "&lt;"));

					// Handles replacements of BUTTON attribute requests
					content = replaceWithReferenceAttributes(content, "BUTTON", $this);
				} finally {

					if(!settings.appendPopoversTo) {
						// Insert content after next block-level element, or after the nearest footnote
						$nearestBlock = $this.closest("p, div, pre, li, ul, section, article, main, aside");
						$siblingFootnote = $nearestBlock.siblings(".footnote-content:last");
						if($siblingFootnote.length > 0) {
							$content = $(content).insertAfter($siblingFootnote);
						} else {
							$content = $(content).insertAfter($nearestBlock);
						}

					} else {
						$content = $(content).appendTo(settings.appendPopoversTo + ":first");
					}

					// Instantiate the max-height for storage and use in repositioning
					$content.attr("data-bigfoot-max-height", $content.height());

					repositionFeet();
					$this.addClass("active");

					// Bind the scroll handler to the popover
					$content.find(".footnote-content-wrapper").bindScrollHandler();
				}
			});

			// Get all footnotes activated by this function
			var $allFootnotesActivated = $(selector.replace(".footnote-button", ".footnote-content"));

			// Add active class after a delay to give it time to transition
			setTimeout(function() {
				$allFootnotesActivated.addClass("active");
			}, settings.popoverCreateDelay);

			return $allFootnotesActivated;
		}


		// FUNCTION ----
		// bindScrollHandler

		// PURPOSE -----
		// Prevents scrolling of the page when you reach the top/ bottom
		// of scrolling a scrollable footnote popover

		// IN ----------
		// Run on popover(s) that are to have the event bound

		// SOURCE ------
		// adapted from: http://stackoverflow.com/questions/16323770/stop-page-from-scrolling-if-hovering-div

		$.fn.bindScrollHandler = function() {
			// Don't even bother checking if option is set to false
			if(!settings.preventPageScroll) { return; }

			$(this).on("DOMMouseScroll mousewheel", function(e) {

				var $this = $(this),
					scrollTop = $this.scrollTop(),
					scrollHeight = $this[0].scrollHeight,
					height = parseInt($this.css("height")),
					$popover = $this.closest(".footnote-content");

				// Fix for Safari 7 not properly calculating scrollHeight()
				// Just add the class as soon as there is any scrolling
				if($this.scrollTop() > 0 && $this.scrollTop() < 10) {
					$popover.addClass("scrollable");
				}

				// Return if the element isn't scrollable
				if(!$popover.hasClass("scrollable")) { return; }

				var delta = (e.type == 'DOMMouseScroll' ?
							 e.originalEvent.detail * -40 :
							 e.originalEvent.wheelDelta), // Get the change in scroll position
					up = delta > 0; // Decide whether the scroll was up or down

				var prevent = function() {
					e.stopPropagation();
					e.preventDefault();
					e.returnValue = false;
					return false;
				}

				if(!up && -delta > scrollHeight - height - scrollTop) {

					// Scrolling down, but this will take us past the bottom.
					$this.scrollTop(scrollHeight);
					$popover.addClass("fully-scrolled"); // Give a class for removal of scroll-related styles
					return prevent();
				} else if(up && delta > scrollTop) {

					// Scrolling up, but this will take us past the top.
					$this.scrollTop(0);
					$popover.removeClass("fully-scrolled");
					return prevent();
				} else {
					$popover.removeClass("fully-scrolled");
				}
			});
		}



		//  ______   ______   ________   ______  _________  ________  __   __   ________   _________  ______
		// /_____/\ /_____/\ /_______/\ /_____/\/________/\/_______/\/_/\ /_/\ /_______/\ /________/\/_____/\
		// \:::_ \ \\::::_\/_\::: _  \ \\:::__\/\__.::.__\/\__.::._\/\:\ \\ \ \\::: _  \ \\__.::.__\/\::::_\/_
		//  \:\ \ \ \\:\/___/\\::(_)  \ \\:\ \  __ \::\ \     \::\ \  \:\ \\ \ \\::(_)  \ \  \::\ \   \:\/___/\
		//   \:\ \ \ \\::___\/_\:: __  \ \\:\ \/_/\ \::\ \    _\::\ \__\:\_/.:\ \\:: __  \ \  \::\ \   \::___\/_
		//    \:\/.:| |\:\____/\\:.\ \  \ \\:\_\ \ \ \::\ \  /__\::\__/\\ ..::/ / \:.\ \  \ \  \::\ \   \:\____/\
		//     \____/_/ \_____\/ \__\/\__\/ \_____\/  \__\/  \________\/ \___/_(   \__\/\__\/   \__\/    \_____\/
		//

		// FUNCTION ----
		// unhoverFeet

		// PURPOSE -----
		// Removes the unhovered footnote content if deleteOnUnhover is true

		// IN ----------
		// Event that contains the target of the mouseout event

		var unhoverFeet = function(e) {
			if(settings.deleteOnUnhover && settings.activateOnHover) {
				setTimeout(function() {
					// If the new element is NOT a descendant of the footnote button
					var $target = $(e.target).closest(".footnote-content, .footnote-button");
					if($(".footnote-button:hover, .footnote-content:hover").length < 1) {
						removePopovers();
					}
				}, settings.hoverDelay);
			}
		}


		// FUNCTION ----
		// escapeKeypress

		// PURPOSE -----
		// Removes all popovers on keypress

		// IN ----------
		// Event that contains the key that was pressed

		var escapeKeypress = function(e) {
			if(e.keyCode == 27) {
				removePopovers();
			}
		}


		// FUNCTION ----
		// removePopovers

		// PURPOSE -----
		// Removes/ adds appropriate classes to the footnote content and button
		// After a delay (to allow for transitions) it removes the actual footnote content

		// IN ----------
		// Selector of footnotes to deactivate and timeout before deleting actual elements

		// OUT ---------
		// Footnote buttons that were deactivated

		function removePopovers(footnotes, timeout) {
			footnotes = footnotes || ".footnote-content";
			timeout = timeout || settings.popoverDeleteDelay;

			$(footnotes).each(function() {
				var $linkedButton = $(".footnote-button[data-footnote-identifier=\"" + $(this).attr("data-footnote-identifier") + "\"]"),
					$this = $(this);
				if($linkedButton.hasClass("changing")) return;
				$linkedButton.removeClass("active hover-instantiated click-instantiated").addClass("changing");
				$this.removeClass("active").addClass("disapearing");

				// Gets rid of the footnote after the timeout
				setTimeout(function() {
					$this.remove();
					$linkedButton.removeClass("changing");
				}, timeout);
			});

			return $(footnotes.replace(".footnote-content", ".footnote-button"));
		}



		//  ______    ______   ______   ______   ______    ________  _________  ________  ______   ___   __
		// /_____/\  /_____/\ /_____/\ /_____/\ /_____/\  /_______/\/________/\/_______/\/_____/\ /__/\ /__/\
		// \:::_ \ \ \::::_\/_\:::_ \ \\:::_ \ \\::::_\/_ \__.::._\/\__.::.__\/\__.::._\/\:::_ \ \\::\_\\  \ \
		//  \:(_) ) )_\:\/___/\\:(_) \ \\:\ \ \ \\:\/___/\   \::\ \    \::\ \     \::\ \  \:\ \ \ \\:. `-\  \ \
		//   \: __ `\ \\::___\/_\: ___\/ \:\ \ \ \\_::._\:\  _\::\ \__  \::\ \    _\::\ \__\:\ \ \ \\:. _    \ \
		//    \ \ `\ \ \\:\____/\\ \ \    \:\_\ \ \ /____\:\/__\::\__/\  \::\ \  /__\::\__/\\:\_\ \ \\. \`-\  \ \
		//     \_\/ \_\/ \_____\/ \_\/     \_____\/ \_____\/\________\/   \__\/  \________\/ \_____\/ \__\/ \__\/
		//


		// FUNCTION ----
		// repositionFeet

		// PURPOSE -----
		// Positions each footnote relative to its button

		var repositionFeet = function() {
			if(settings.positionContent) {

				$(".footnote-content").each(function() {

					// Element Definitions
					var $this 				= $(this),
						dataIdentifier 		= "data-footnote-identifier=\"" + $this.attr("data-footnote-identifier") + "\"",
						$contentWrapper 	= $this.find(".footnote-content-wrapper"),
						$button 			= $(".footnote-button[" + dataIdentifier + "]");

					// Spacing Information
					var roomLeft 			= roomCalc($button),
						contentWidth 		= parseFloat($this.css("width")),
						marginSize 			= parseFloat($this.css("margin-top")),
						maxHeightInCSS 		= +($this.attr("data-bigfoot-max-height")),
						totalHeightInCSS	= 2*marginSize + maxHeightInCSS,
						maxHeightOnScreen 	= 10000;

					// Position tooltip on top if:
					// total space on bottom is not enough to hold footnote AND
					// top room is larger than bottom room
					if(roomLeft.bottomRoom < totalHeightInCSS && roomLeft.topRoom > roomLeft.bottomRoom) {
						$this.css({"top": "auto", "bottom": roomLeft.bottomRoom + "px"}).addClass("top").removeClass("bottom");
						maxHeightOnScreen = roomLeft.topRoom - marginSize - 15;
						$this.css({"transform-origin": (roomLeft.leftRelative*100) + "% 100%"});
					} else {
						$this.css({"bottom": "auto", "top": roomLeft.topRoom + "px"}).addClass("bottom").removeClass("top");
						maxHeightOnScreen = roomLeft.bottomRoom - marginSize - 15;
						$this.css({"transform-origin": (roomLeft.leftRelative*100) + "% 0%"});
					}

					// Sets the max height so that there is no footnote overflow
					$this.find(".footnote-content-wrapper").css({"max-height": Math.min(maxHeightOnScreen, maxHeightInCSS) + "px"});

					// Positions the popover
					$this.css({"left": (roomLeft.leftRoom - (roomLeft.leftRelative * contentWidth)) + "px"});

					// Position the tooltip
					positionTooltip($this, roomLeft.leftRelative);

					// Give scrollable class if the content hight is larger than the container
					if(parseInt($this.css("height")) < $this.find(".footnote-content-wrapper")[0].scrollHeight) {
						$this.addClass("scrollable");
					}
				});
			}
		}


		// FUNCTION ----
		// positionTooltip

		// PURPOSE -----
		// Positions the tooltip at the same relative horizontal position as the button

		// IN ----------
		// Footnote popover to get the tooltip of and the relative horizontal position (as a decimal)

		function positionTooltip($popover, leftRelative) {
			leftRelative = leftRelative || 0.5; // default to 50%
			var $tooltip = $popover.find(".tooltip");

			if($tooltip.length > 0) {
				$tooltip.css({"left": leftRelative*100 + "%"});
			}
		}


		// FUNCTION ----
		// roomCalc

		// PURPOSE -----
		// Calculates area on the top, left, bottom and right of the element
		// Also calculates the relative position to the left and top of the screen

		// IN ----------
		// Element to calculate screen position of

		// OUT ---------
		// Object containing room on all sides and top/ left relative positions
		// All measurements are relative to the middle of the element

		function roomCalc($el) {
			var elWidth		= parseFloat($el.outerWidth()),
				elHeight	= parseFloat($el.outerHeight()),
				w 			= viewportSize(),
				topRoom		= $el.offset().top - $(window).scrollTop() + elHeight/2,
				leftRoom	= $el.offset().left + elWidth/2;

			return {
				topRoom			: topRoom,
				bottomRoom		: w.height - topRoom,
				leftRoom		: leftRoom,
				rightRoom		: w.width - leftRoom,
				leftRelative	: leftRoom / w.width,
				topRelative		: topRoom / w.height
			};
		}


		// FUNCTION ----
		// viewportSize

		// PURPOSE -----
		// Calculates the height and width of the viewport

		// OUT ---------
		// Object with .width and .height properties

		function viewportSize() {
			var test = document.createElement("div");

			test.style.cssText = "position: fixed;top: 0;left: 0;bottom: 0;right: 0;";
			document.documentElement.insertBefore(test, document.documentElement.firstChild);

			var dims = { width: test.offsetWidth, height: test.offsetHeight };
			document.documentElement.removeChild(test);

			return dims;
		}



		//  ______   _________  ___   ___   ______   ______
		// /_____/\ /________/\/__/\ /__/\ /_____/\ /_____/\
		// \:::_ \ \\__.::.__\/\::\ \\  \ \\::::_\/_\:::_ \ \
		//  \:\ \ \ \  \::\ \   \::\/_\ .\ \\:\/___/\\:(_) ) )_
		//   \:\ \ \ \  \::\ \   \:: ___::\ \\::___\/_\: __ `\ \
		//    \:\_\ \ \  \::\ \   \: \ \\::\ \\:\____/\\ \ `\ \ \
		//     \_____\/   \__\/    \__\/ \::\/ \_____\/ \_\/ \_\/
		//


		// FUNCTION ----
		// updateSetting

		// PURPOSE -----
		// Updates the specified setting with the value you pass

		// IN ----------
		// Setting to adjust and new value for the setting

		// OUT ---------
		// Returns the old value for the setting

		var updateSetting = function(setting, value) {
			var oldValue = settings[setting];
			settings[setting] = value;
			return oldValue;
		}


		// FUNCTION ----
		// getSetting

		// PURPOSE -----
		// Returns the settings object

		var getSetting = function(setting) {

			return settings[setting];
		}



		//   _______    ________  ___   __    ______    ________  ___   __    _______
		// /_______/\  /_______/\/__/\ /__/\ /_____/\  /_______/\/__/\ /__/\ /______/\
		// \::: _  \ \ \__.::._\/\::\_\\  \ \\:::_ \ \ \__.::._\/\::\_\\  \ \\::::__\/__
		//  \::(_)  \/_   \::\ \  \:. `-\  \ \\:\ \ \ \   \::\ \  \:. `-\  \ \\:\ /____/\
		//   \::  _  \ \  _\::\ \__\:. _    \ \\:\ \ \ \  _\::\ \__\:. _    \ \\:\\_  _\/
		//    \::(_)  \ \/__\::\__/\\. \`-\  \ \\:\/.:| |/__\::\__/\\. \`-\  \ \\:\_\ \ \
		//     \_______\/\________\/ \__\/ \__\/ \____/_/\________\/ \__\/ \__\/ \_____\/
		//

		$(document).ready(function() {

			footnoteInit();

			$(document).on("mouseenter", ".footnote-button", buttonHover);
			$(document).on("touchend click", touchClick);
			$(document).on("mouseout", ".hover-instantiated", unhoverFeet);
			$(document).on("keyup", escapeKeypress);
			$(window).on("scroll resize", repositionFeet);
		});



		//  ______    ______   _________  __  __   ______    ___   __
		// /_____/\  /_____/\ /________/\/_/\/_/\ /_____/\  /__/\ /__/\
		// \:::_ \ \ \::::_\/_\__.::.__\/\:\ \:\ \\:::_ \ \ \::\_\\  \ \
		//  \:(_) ) )_\:\/___/\  \::\ \   \:\ \:\ \\:(_) ) )_\:. `-\  \ \
		//   \: __ `\ \\::___\/_  \::\ \   \:\ \:\ \\: __ `\ \\:. _    \ \
		//    \ \ `\ \ \\:\____/\  \::\ \   \:\_\:\ \\ \ `\ \ \\. \`-\  \ \
		//     \_\/ \_\/ \_____\/   \__\/    \_____\/ \_\/ \_\/ \__\/ \__\/
		//

		return {
			close: function(footnotes, timeout) {
				return removePopovers(footnotes, timeout);
			},
			activate: function(button) {
				return createPopover(button);
			},
			reposition: function() {
				return repositionFeet();
			},
			getSetting: function(setting) {
				return getSetting(setting);
			},
			updateSetting: function(setting, newValue) {
				return updateSetting(setting, newValue);
			}
		}
	};

})(jQuery);