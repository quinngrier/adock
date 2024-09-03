#! /usr/bin/env node
//
// The authors of this file have waived all copyright and
// related or neighboring rights to the extent permitted by
// law as described by the CC0 1.0 Universal Public Domain
// Dedication. You should have received a copy of the full
// dedication along with this file, typically as a file
// named <CC0-1.0.txt>. If not, it may be available at
// <https://creativecommons.org/publicdomain/zero/1.0/>.
//

const fs = require("node:fs");
const path = require("node:path");
const puppeteer = require("puppeteer");

let src_file = undefined;
let dst_file = undefined;
let dst_type = undefined;

let args = process.argv.slice(2);
while (args.length > 0) {
  if (args[0] === "-o") {
    if (dst_file !== undefined) {
      throw new Error("dst_file specified more than once");
    }
    dst_file = args[1];
    args = args.slice(2);
  } else if (args[0] === "-t") {
    if (dst_type !== undefined) {
      throw new Error("dst_type specified more than once");
    }
    dst_type = args[1];
    args = args.slice(2);
  } else {
    if (src_file !== undefined) {
      throw new Error("src_file specified more than once");
    }
    src_file = args[0];
    args = args.slice(1);
  }
}
if (src_file === undefined) {
  throw new Error("src_file not specified");
}
if (dst_file === undefined) {
  throw new Error("dst_file not specified");
}
if (dst_type === undefined) {
  throw new Error("dst_type not specified");
}

if (dst_type !== "png") {
  throw new Error("dst_type must be png");
}

dst_file = path.resolve(dst_file);

const dst_name = path.basename(dst_file);

const src_xml = fs.readFileSync(src_file, {encoding: "utf8"});

const lib_css = path.resolve(__dirname, "bpmn-js.css");
const tmp_css = `${dst_file}.tmp.css`;
fs.copyFileSync(lib_css, tmp_css);

const lib_js = path.resolve(__dirname, "bpmn-viewer.production.min.js");
const tmp_js = `${dst_file}.tmp.js`;
fs.copyFileSync(lib_js, tmp_js);

const tmp_html = `${dst_file}.tmp.html`;
fs.writeFileSync(tmp_html, `
  <!DOCTYPE html>
  <html>
    <head>
      <link rel="stylesheet" href="${dst_name}.tmp.css">
      <script src="${dst_name}.tmp.js"></script>
    </head>
    <body>
      <div id="canvas"></div>
    </body>
  </html>
`);

(async () => {
  const browser_args = [
    "--disable-gpu",
  ];
  if (process.env.IN_ADOCK) {
    browser_args.push("--no-sandbox");
  }
  const browser = await puppeteer.launch({
    args: browser_args,
  });
  const page = await browser.newPage();
  await page.setViewport({
    width: 1000,
    height: 3000,
    deviceScaleFactor: 3,
  });
  await page.goto(`file://${tmp_html}`);
  await page.evaluate(async (src_xml) => {
    try {
      const viewer = new BpmnJS({container: "#canvas"});
      await viewer.importXML(src_xml);
      viewer.get("canvas").zoom("fit-viewport", "auto");
    } catch (e) {
      document.getElementById("canvas").textContent = e.toString();
    }
  }, src_xml);
  const canvas = await page.$("#canvas");
  await canvas.screenshot({path: `${dst_file}.tmp`});
  await browser.close();
  fs.rmSync(tmp_css);
  fs.rmSync(tmp_js);
  fs.rmSync(tmp_html);
  fs.renameSync(`${dst_file}.tmp`, dst_file);
})();
