const fs = require('fs');
let plist = fs.readFileSync('ios/Runner/Info.plist', 'utf8');

if (!plist.includes('BGTaskSchedulerPermittedIdentifiers')) {
  plist = plist.replace(
    '</dict>\n</plist>',
    `	<key>BGTaskSchedulerPermittedIdentifiers</key>\n	<array>\n		<string>com.salesman.background</string>\n	</array>\n</dict>\n</plist>`
  );
  fs.writeFileSync('ios/Runner/Info.plist', plist);
  console.log('Patched Info.plist');
} else {
  console.log('Already patched');
}
