const sql = require('mssql');
const config = require('./config.js');

async function test() {
  try {
    await sql.connect(config);
    const result = await sql.query(`
      SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME LIKE '%inv%' OR TABLE_NAME LIKE '%cus%' OR TABLE_NAME LIKE '%bal%'
    `);
    console.table(result.recordset);
  } catch (e) {
    console.error(e);
  } finally {
    process.exit();
  }
}
test();
