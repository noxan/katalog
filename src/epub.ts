import { FileEntry, readBinaryFile } from "@tauri-apps/api/fs";
import { unzip as unzipcb, Unzipped, strFromU8 } from "fflate/browser";
import { XMLParser } from "fast-xml-parser";

const unzip = (buffer: Uint8Array): Promise<Unzipped> =>
  new Promise((resolve, reject) =>
    unzipcb(buffer, (err, data) => (err ? reject(err) : resolve(data)))
  );

const readXml = (xml: string) => {
  const parser = new XMLParser({ ignoreAttributes: false });
  return parser.parse(xml);
};

const findOpfFile = (zip: Unzipped) => {
  const opfFilePath = "META-INF/container.xml";
  const text = strFromU8(zip[opfFilePath]);
  const xml = readXml(text);
  return xml.container.rootfiles.rootfile["@_full-path"];
};

const readOpfFile = (zip: Unzipped, opfFilePath: string) => {
  const text = strFromU8(zip[opfFilePath]);
  const xml = readXml(text);
  return xml.package;
};

export const readEpub = async (entry: FileEntry) => {
  const buffer = await readBinaryFile(entry.path);
  const zip = await unzip(buffer);

  const opfFilePath = findOpfFile(zip);
  const opfFile = readOpfFile(zip, opfFilePath);
  console.log(opfFile);

  return opfFile;
};
