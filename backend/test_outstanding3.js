const sql = require('mssql');
const config = require('./config.js');

async function test() {
  try {
    await sql.connect(config);
    const result = await sql.query(`
      SELECT CustomerCode, CustomerName, Location, CostCenter FROM gen_customer WHERE CustomerCode = 'C2174'
    `);
    console.log("Customer C2174:", JSON.stringify(result.recordset, null, 2));

    // Try testing the stored procedure again with this customer's actual Location and CostCenter
    if (result.recordset.length > 0) {
      const loc = result.recordset[0].Location || '01';
      const cc = result.recordset[0].CostCenter || '000001';
      
      const transUniqId = 'TEST_UNQ_' + Math.floor(Math.random() * 1000);
      const request = new sql.Request();
      request.input('p_AccCode1', sql.VarChar, 'C2174');
      request.input('p_AccCode2', sql.VarChar, 'C2174');
      request.input('p_Sdate', sql.DateTime, new Date('2000-01-01'));
      request.input('p_Edate', sql.DateTime, new Date());
      request.input('p_LocaCode', sql.VarChar, '');  // Try empty location to see if it brings all? Or the actual one?
      request.input('p_CostCenter', sql.VarChar, ''); 
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
      console.log("Calculated Total (Empty Loc/CC):", result2.recordset[0].Total);

      // cleanup
      await new sql.Request()
        .input('TransUniqId', sql.VarChar(20), transUniqId)
        .query('DELETE FROM inv_temppaymentdetails WHERE TempDocNo = @TransUniqId');
    }

  } catch (e) {
    console.error(e);
  } finally {
    process.exit();
  }
}
test();
