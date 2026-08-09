const api = globalThis.browser ?? globalThis.chrome;

function commandURL(url, forcePrompt = false) {
  const params = new URLSearchParams();
  params.set("source", "browser-extension");
  params.set("url", url);
  if (forcePrompt) params.set("prompt", "1");
  return `potliji-link://open?${params.toString()}`;
}

async function activeTab() {
  const tabs = await api.tabs.query({ active: true, currentWindow: true });
  return tabs[0];
}

async function handOff(url, forcePrompt = false) {
  if (!url || !/^https?:/i.test(url)) return;
  const bridge = api.runtime.getURL(`bridge.html?target=${encodeURIComponent(commandURL(url, forcePrompt))}`);
  await api.tabs.create({ url: bridge, active: false });
}

api.runtime.onInstalled.addListener(() => {
  api.contextMenus.create({
    id: "potliji-open-link",
    title: "Open Link with PotliJi",
    contexts: ["link"]
  });
  api.contextMenus.create({
    id: "potliji-open-link-picker",
    title: "Open Link with PotliJi Picker",
    contexts: ["link"]
  });
  api.contextMenus.create({
    id: "potliji-open-page",
    title: "Open Page with PotliJi",
    contexts: ["page"]
  });
  api.contextMenus.create({
    id: "potliji-open-page-picker",
    title: "Open Page with PotliJi Picker",
    contexts: ["page"]
  });
});

// The toolbar action follows the host app's “always open the picker” setting.
api.action.onClicked.addListener((tab) => handOff(tab.url, false));

api.contextMenus.onClicked.addListener((info, tab) => {
  const isLink = info.menuItemId === "potliji-open-link"
    || info.menuItemId === "potliji-open-link-picker";
  const forcePrompt = info.menuItemId === "potliji-open-link-picker"
    || info.menuItemId === "potliji-open-page-picker";
  const url = isLink ? info.linkUrl : tab?.url;
  handOff(url, forcePrompt);
});

api.commands.onCommand.addListener(async (command) => {
  const tab = await activeTab();
  if (command === "open-current-page") handOff(tab?.url, false);
  if (command === "open-current-page-picker") handOff(tab?.url, true);
});
