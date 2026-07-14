export const DEFAULT_CONFIG = Object.freeze({
  enabled: false,
  deviceMode: "mock",
  sessionMinutes: 45,
  leaveGraceSeconds: 300,
  distractionGraceSeconds: 120,
  idleGraceSeconds: 600,
  cooldownSeconds: 180,
  maxTriggersPerSession: 5,
  maxIntensity: 60,
  maxDurationMs: 5000,
  emergencyStopKey: "Ctrl+Alt+S",
  privacy: {
    saveWindowTitles: false,
    saveUrls: false,
    readBrowserUrl: false
  },
  writingScope: [],
  distractionScope: [],
  ignoreScope: [],
  pauseScope: [],
  triggers: {
    FOCUS_LEFT: {
      intensityRange: [20, 30],
      durationRangeMs: [1000, 2000]
    },
    DISTRACTION_DETECTED: {
      intensityRange: [30, 45],
      durationRangeMs: [1500, 3000]
    },
    IDLE_TOO_LONG: {
      intensityRange: [15, 25],
      durationRangeMs: [1000, 2000]
    },
    SESSION_TIMEOUT: {
      intensityRange: [25, 40],
      durationRangeMs: [2000, 4000]
    },
    MANUAL_TEST: {
      intensityRange: [10, 10],
      durationRangeMs: [1000, 1000]
    }
  },
  coyote: {
    transport: "websocket",
    endpoint: "ws://127.0.0.1:8080",
    pairingToken: "",
    channel: "both",
    pattern: "constant"
  }
});

export const SAFE_DEFAULT_CONFIG = Object.freeze({
  ...DEFAULT_CONFIG,
  enabled: false,
  deviceMode: "mock",
  maxIntensity: 30,
  maxDurationMs: 1000,
  writingScope: [],
  distractionScope: [],
  ignoreScope: [],
  pauseScope: []
});
