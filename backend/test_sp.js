const sql = require('mssql');
const config = require('./config.js');

async function test() {
  try {
    await sql.connect(config);
    const result = await sql.query(`
      SELECT OBJECT_DEFINITION(OBJECT_ID('inv_USp_AccBalanceReport')) AS sp_code
    `);
    console.log(result.recordset[0].sp_code);
  } catch (e) {
    console.error(e);
  } finally {
    process.exit();
  }
}
test();
