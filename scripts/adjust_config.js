const fs = require("fs");

const filePath = "../firebase-new/firebase.json"; // 路径根据你的项目结构调整

const latestFileURL = process.argv[2];
if (!latestFileURL) throw "No latestFileURL";

// 读取firebase.json文件
const data = fs.readFileSync(filePath, "utf8");

let config = JSON.parse(data);
config.hosting.redirects = [
  {
    source: "/downloads/latest",
    destination: `/downloads/${latestFileURL}`,
    type: 301,
  },
];
const updatedConfig = JSON.stringify(config, null, 2);
console.log("updatedConfig", updatedConfig);
// 写回文件
fs.writeFile(filePath, updatedConfig, "utf8", (err) => {
  if (err) {
    console.error("Error writing back to firebase.json:", err);
  } else {
    console.log("firebase.json has been updated with new redirects.");
  }
});
