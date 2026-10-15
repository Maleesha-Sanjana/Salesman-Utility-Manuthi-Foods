const fs = require('fs');
let code = fs.readFileSync('backend/server.js', 'utf8');

code = code.replace(
  'await transaction.commit();',
  `// Explicitly enforce isPending = 1 for this new Sales Order
      await new sql.Request(transaction)
        .input('orgDocNo', sql.VarChar(20), generatedOrgDocNo)
        .query(\`
          UPDATE inv_invoiceheader
          SET isPending = 1, isApproved = 0, isReject = 0, rejReason = NULL
          WHERE DocumentNo = @orgDocNo AND (Iid = 'SO' OR Iid = 'SON')
        \`);

      await transaction.commit();`
);

fs.writeFileSync('backend/server.js', code);
console.log('Patched');
