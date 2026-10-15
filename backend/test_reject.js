const sql = require('mssql');
const config = require('./config.js');

async function testReject() {
  try {
    let pool = await sql.connect(config);
    let result = await pool.request()
      .input('documentNo', sql.VarChar, '01SO00000023')
      .input('reason', sql.NVarChar, 'Test rejection reason')
      .query(`
        UPDATE inv_invoiceheader 
        SET isApproved = 0, isPending = 0, isReject = 1, rejReason = @reason 
        WHERE DocumentNo = @documentNo AND (Iid = 'SO' OR Iid = 'SON')
      `);
    console.log('Rows affected:', result.rowsAffected);
    
    let check = await pool.request()
      .input('docNo', sql.VarChar, '01SO00000023')
      .query('SELECT DocumentNo, isPending, isApproved, isReject, rejReason FROM inv_invoiceheader WHERE DocumentNo = @docNo');
    console.log(check.recordset);
    process.exit(0);
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
}
testReject();
