export class EventBus {
  constructor() {
    this.handlers = new Map();
  }

  on(type, handler) {
    const handlers = this.handlers.get(type) ?? new Set();
    handlers.add(handler);
    this.handlers.set(type, handlers);
    return () => handlers.delete(handler);
  }

  async emit(type, payload) {
    const handlers = this.handlers.get(type);
    if (!handlers) return;
    for (const handler of handlers) {
      await handler(payload);
    }
  }
}
