import { FileEntry, readBinaryFile } from "@tauri-apps/api/fs";
import { dirname, join } from "@tauri-apps/api/path";
import { unzip as unzipcb, Unzipped, strFromU8 } from "fflate/browser";
import { XMLParser } from "fast-xml-parser";
import * as base64 from "byte-base64";

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

const ensureArray = (obj: any) => (obj instanceof Array ? obj : [obj]);

const findCoverImageId = (meta: object[]) => {
  if (!meta) {
    return "cover";
  }

  const metaArray = ensureArray(meta);
  const coverImageObject: any = metaArray.find(
    (item: any) => item["@_name"] === "cover"
  );
  return coverImageObject?.["@_content"] || "cover";
};

export const readEpub = async (entry: FileEntry) => {
  const buffer = await readBinaryFile(entry.path);
  const zip = await unzip(buffer);

  const opfFilePath = findOpfFile(zip);
  // console.log(opfFilePath);
  const opfFile = readOpfFile(zip, opfFilePath);
  // console.log(opfFile);
  const directory = await dirname(opfFilePath);

  const coverImageId = findCoverImageId(opfFile.metadata.meta);
  if (coverImageId) {
    const coverImageItem = opfFile.manifest.item.find(
      (item: any) => item["@_id"] === coverImageId
    );
    const coverImageHref = coverImageItem["@_href"];
    const coverImagePath =
      directory === "" ? coverImageHref : await join(directory, coverImageHref);
    console.log(coverImagePath, coverImagePath in zip);

    const bytes = zip[coverImagePath];
    const coverImageBase64: string = await base64.bytesToBase64(bytes);
    const coverImage =
      "data:image/jpg;charset=utf-8;base64," + coverImageBase64;

    opfFile.coverImage = coverImage;
  }

  return opfFile;
};
