export class ManualWindowMonitor {
  constructor() {
    this.currentWindow = {
      processName: "unknown",
      title: "",
      url: "",
      capturedAt: new Date().toISOString()
    };
    this.handlers = new Set();
  }

  start() {}

  stop() {}

  async getCurrentWindow() {
    return this.currentWindow;
  }

  onChange(handler) {
    this.handlers.add(handler);
    return () => this.handlers.delete(handler);
  }

  setCurrentWindow(info) {
    this.currentWindow = {
      processName: info.processName ?? "unknown",
      title: info.title ?? "",
      url: info.url ?? "",
      capturedAt: new Date().toISOString()
    };
    for (const handler of this.handlers) {
      handler(this.currentWindow);
    }
  }
}
