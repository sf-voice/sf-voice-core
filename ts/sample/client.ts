import { SfVoiceMedia } from "../sdk/src/index.js";
import { config } from "./config.ts";

// single shared client — all routes import from here
export const sfVoice = new SfVoiceMedia(config.sfVoice);
