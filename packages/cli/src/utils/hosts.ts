import { getManagedHostnames, syncHostsFile } from "portless";

export function readHostnames() {
  getManagedHostnames();
}

export function writeHostName(hostnames: string[]) {
  syncHostsFile(hostnames);
}
