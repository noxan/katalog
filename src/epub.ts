import { FileEntry, readBinaryFile } from "@tauri-apps/api/fs";
import { unzip as unzipcb, Unzipped } from "fflate/browser";

const unzip = (buffer: Uint8Array): Promise<Unzipped> =>
  new Promise((resolve, reject) =>
    unzipcb(buffer, (err, data) => (err ? reject(err) : resolve(data)))
  );

export const readEpub = async (entry: FileEntry) => {
  const buffer = await readBinaryFile(entry.path);
  const unzipped = await unzip(buffer);
  console.log(unzipped);
};
