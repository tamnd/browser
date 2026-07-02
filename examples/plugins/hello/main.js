// Copy this folder into your profile's plugins/ directory and add
// "hello" to plugins.enabled in config.json.

function onload() {
  browser.commands.register("hello.greet", "Say Hello", function () {
    var count = (browser.storage.get("count") || 0) + 1;
    browser.storage.set("count", count);
    browser.ui.notify("hello from a plugin, run #" + count + " on browser " + browser.version);
  });

  browser.commands.register("hello.docs", "Open WebKit Docs", function () {
    browser.tabs.open("https://developer.apple.com/documentation/webkit/wkwebview");
  });

  // Events fire for tab.created, tab.closed, tab.activated,
  // workspace.switched, navigation.committed, download.finished.
  browser.events.on("download.finished", function (payload) {
    if (!payload.error) {
      browser.ui.notify("downloaded " + payload.filename);
    }
  });

  // Styles apply on the next page load; the host list is optional.
  browser.styles.register("calm-docs", "body { text-rendering: optimizeLegibility; }", ["developer.apple.com"]);
}

function onunload() {
  browser.styles.unregister("calm-docs");
}
