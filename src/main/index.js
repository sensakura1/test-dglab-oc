import { AppController } from "./appController.js";

const app = new AppController();
await app.init();
await app.startFocus();

const result = await app.manualTest();
console.log(JSON.stringify({
  message: "OC writing focus helper core started.",
  manualTest: result,
  snapshot: app.getSnapshot()
}, null, 2));
