const sql = require('mssql');
const config = require('./config.js');

async function test() {
  try {
    await sql.connect(config);
    const customerCode = 'C2174';
    const transUniqId = 'TEST_UNQ_' + Math.floor(Math.random() * 1000);
    
    const request = new sql.Request();
    request.input('p_AccCode1', sql.VarChar, customerCode);
    request.input('p_AccCode2', sql.VarChar, customerCode);
    // PASS TODAY'S DATE to p_Sdate since the SP uses it as the "As Of" date!
    request.input('p_Sdate', sql.DateTime, new Date()); 
    request.input('p_Edate', sql.DateTime, new Date());
    request.input('p_LocaCode', sql.VarChar, '01');
    request.input('p_CostCenter', sql.VarChar, '000001');
    request.input('p_WithoutPd', sql.Bit, 0);
    request.input('p_TransUniqId', sql.VarChar, transUniqId);
    request.input('p_Tid', sql.Int, 0);
    
    await request.execute('inv_USp_AccBalanceReport');
    
    const result2 = await new sql.Request()
      .input('TransUniqId', sql.VarChar(20), transUniqId)
      .query(`
        SELECT isnull(sum(it.BalanceAmount),0) as Total 
        FROM inv_temppaymentdetails it 
        WHERE TempDocNo = @TransUniqId 
        AND (it.Iid='INV' OR it.Iid='CRN' OR it.Iid='CRR' OR it.Iid='ACR')
      `);
      
    console.log("Calculated Total with correct Sdate:", result2.recordset[0].Total);

    // cleanup
    await new sql.Request()
      .input('TransUniqId', sql.VarChar(20), transUniqId)
      .query('DELETE FROM inv_temppaymentdetails WHERE TempDocNo = @TransUniqId');
      
  } catch (e) {
    console.error(e);
  } finally {
    process.exit();
  }
}
test();
