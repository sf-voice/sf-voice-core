type LogFields = Record<string, unknown>;

function write(level: string, message: string, fields: LogFields = {}): void {
   const payload = {
      level,
      message,
      ...fields,
   };
   const line = JSON.stringify(payload);

   if (level === "error") {
      console.error(line);
      return;
   }

   if (level === "warn") {
      console.warn(line);
      return;
   }

   console.log(line);
}

export const log = {
   debug(message: string, fields?: LogFields) {
      if (process.env.LOG_LEVEL === "debug") write("debug", message, fields);
   },
   info(message: string, fields?: LogFields) {
      write("info", message, fields);
   },
   warn(message: string, fields?: LogFields) {
      write("warn", message, fields);
   },
   error(message: string, fields?: LogFields) {
      write("error", message, fields);
   },
};
