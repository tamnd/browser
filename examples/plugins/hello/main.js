// Copy this folder into your profile's plugins/ directory and add
// "hello" to plugins.enabled in config.json.

function onload() {
  browser.commands.register("hello.greet", "Say Hello", function () {
    var count = (browser.storage.get("count") || 0) + 1;
    browser.storage.set("count", count);
    browser.ui.notify("hello from a plugin, run #" + count);
  });

  browser.commands.register("hello.docs", "Open WebKit Docs", function () {
    browser.tabs.open("https://developer.apple.com/documentation/webkit/wkwebview");
  });
}
