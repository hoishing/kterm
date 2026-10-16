// The shortcut (or toolbar button) grants activeTab for the current tab, so
// no host permissions are needed. grab.js runs in the page's main world so
// it can read React fibers; running it again toggles the picker off.
async function grab(tab) {
  if (!tab || tab.id === undefined) return;
  try {
    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      files: ["grab.js"],
      world: "MAIN",
    });
  } catch (error) {
    // chrome:// pages, the Web Store, the PDF viewer, …
    console.warn("kterm grab: cannot run on this page:", error);
  }
}

chrome.commands.onCommand.addListener((command, tab) => {
  if (command === "grab") grab(tab);
});
chrome.action.onClicked.addListener(grab);
