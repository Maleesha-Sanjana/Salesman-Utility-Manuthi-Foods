const sql = require('mssql');

async function initializeDatabase(pool) {
  if (!pool) return false;

  console.log('🔄 Running database schema initialization...');

  try {
    // 1. gen_userLoc Table
    await pool.request().query(`
      IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='gen_userLoc' AND xtype='U')
      CREATE TABLE gen_userLoc (
        id INT IDENTITY(1,1) PRIMARY KEY,
        userCode NVARCHAR(50) NOT NULL,
        userName NVARCHAR(100) NOT NULL,
        latitude FLOAT NOT NULL,
        longitude FLOAT NOT NULL,
        accuracy FLOAT NULL DEFAULT 0,
        speed FLOAT NULL DEFAULT 0,
        heading FLOAT NULL DEFAULT 0,
        address NVARCHAR(255) NULL,
        timestamp DATETIME2 NOT NULL DEFAULT GETDATE(),
        created_at DATETIME2 NOT NULL DEFAULT GETDATE(),
        updated_at DATETIME2 NOT NULL DEFAULT GETDATE(),
        isActive BIT NOT NULL DEFAULT 1,
        CONSTRAINT UQ_gen_userLoc_userCode UNIQUE (userCode)
      )
    `);
    console.log('✅ Location tracking table ready');

    // 2. gen_customer Alterations
    await pool.request().query(`
      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_customer') AND name = 'Latitude')
        ALTER TABLE dbo.gen_customer ADD Latitude DECIMAL(10, 8) NULL;

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_customer') AND name = 'Longitude')
        ALTER TABLE dbo.gen_customer ADD Longitude DECIMAL(11, 8) NULL;
        
      IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_customer') AND name = 'CustomerId' AND max_length < 30)
        ALTER TABLE dbo.gen_customer ALTER COLUMN CustomerId NVARCHAR(15) NULL;

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_customer') AND name = 'CreatedSalesman')
        ALTER TABLE dbo.gen_customer ADD CreatedSalesman NVARCHAR(15) NULL;

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_customer') AND name = 'Assigned')
        ALTER TABLE dbo.gen_customer ADD Assigned NVARCHAR(50) NULL;
      ELSE IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_customer') AND name = 'Assigned' AND is_nullable = 0)
        BEGIN TRY
          ALTER TABLE dbo.gen_customer ALTER COLUMN Assigned NVARCHAR(50) NULL;
        END TRY
        BEGIN CATCH
        END CATCH
    `);
    console.log('✅ Customer table schema updated');

    // 3. gen_userDevice Table
    await pool.request().query(`
      IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='gen_userDevice' AND xtype='U')
      BEGIN
        CREATE TABLE gen_userDevice (
            id INT IDENTITY(1,1) PRIMARY KEY,
            deviceId NVARCHAR(100) NOT NULL,
            userCode NVARCHAR(50) NOT NULL,
            userName NVARCHAR(100) NOT NULL,
            deviceName NVARCHAR(100) NULL,
            deviceModel NVARCHAR(100) NULL,
            platform NVARCHAR(20) NULL,        -- android, ios, web
            osVersion NVARCHAR(50) NULL,
            appVersion NVARCHAR(20) NULL,
            isAdmin BIT NOT NULL DEFAULT 0,
            isSuper BIT NOT NULL DEFAULT 0,
            firstSeenAt DATETIME2 NOT NULL DEFAULT GETDATE(),
            lastSeenAt DATETIME2 NOT NULL DEFAULT GETDATE(),
            isActive BIT NOT NULL DEFAULT 1,
            CONSTRAINT UQ_gen_userDevice_deviceId UNIQUE (deviceId)
        );
        CREATE INDEX IX_gen_userDevice_lastSeenAt ON gen_userDevice (lastSeenAt DESC, isActive);
      END
      
      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_userDevice') AND name = 'isAllowed')
        ALTER TABLE gen_userDevice ADD isAllowed BIT NOT NULL CONSTRAINT DF_gen_userDevice_isAllowed DEFAULT 1;

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_userDevice') AND name = 'approvedAt')
        ALTER TABLE gen_userDevice ADD approvedAt DATETIME2 NULL;

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_userDevice') AND name = 'approvedBy')
        ALTER TABLE gen_userDevice ADD approvedBy NVARCHAR(100) NULL;
    `);
    console.log('✅ User Device tracking table ready');

    // 4. gen_salesman Alterations
    await pool.request().query(`
      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_salesman') AND name = 'isAdmin')
        ALTER TABLE gen_salesman ADD isAdmin BIT NOT NULL CONSTRAINT DF_gen_salesman_isAdmin DEFAULT 0;

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_salesman') AND name = 'isSuper')
        ALTER TABLE gen_salesman ADD isSuper BIT NOT NULL CONSTRAINT DF_gen_salesman_isSuper DEFAULT 0;
        
      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_salesman') AND name = 'password')
        ALTER TABLE gen_salesman ADD password NVARCHAR(255) NULL;

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_salesman') AND name = 'salesmanImg')
        ALTER TABLE gen_salesman ADD salesmanImg VARBINARY(MAX) NULL;

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_salesman') AND name = 'isLogged')
        ALTER TABLE gen_salesman ADD isLogged BIT NOT NULL CONSTRAINT DF_gen_salesman_isLogged DEFAULT 0;

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_salesman') AND name = 'userName')
        ALTER TABLE gen_salesman ADD userName NVARCHAR(50) NULL;
    `);
    console.log('✅ Salesman table schema updated');

    // 5. gen_salesmanPlaceCheckIn Table
    await pool.request().query(`
      IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='gen_salesmanPlaceCheckIn' AND xtype='U')
      BEGIN
        CREATE TABLE gen_salesmanPlaceCheckIn (
          id INT IDENTITY(1,1) PRIMARY KEY,
          SalesmanCode NVARCHAR(15) NOT NULL,
          SalesmanName NVARCHAR(100) NULL,
          PlaceName NVARCHAR(100) NOT NULL,
          Latitude DECIMAL(10, 8) NOT NULL,
          Longitude DECIMAL(11, 8) NOT NULL,
          Accuracy FLOAT NULL DEFAULT 0,
          Remarks NVARCHAR(255) NULL,
          CheckedInAt DATETIME2 NOT NULL DEFAULT GETDATE(),
          Created_Date DATETIME2 NOT NULL DEFAULT GETDATE()
        );

        CREATE INDEX IX_gen_salesmanPlaceCheckIn_SalesmanCode_CheckedInAt
          ON gen_salesmanPlaceCheckIn (SalesmanCode, CheckedInAt DESC);
      END
    `);
    console.log('✅ Salesman place check-in table ready');

    // 6. gen_salesmanUseRights Table
    await pool.request().query(`
      IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='gen_salesmanUseRights' AND xtype='U')
      CREATE TABLE gen_salesmanUseRights (
        SalesmanCode NVARCHAR(15) NOT NULL PRIMARY KEY,
        CanSalesOrder BIT NOT NULL CONSTRAINT DF_gen_salesmanUseRights_CanSalesOrder DEFAULT (1),
        CanInvoice BIT NOT NULL CONSTRAINT DF_gen_salesmanUseRights_CanInvoice DEFAULT (1),
        CanQuotation BIT NOT NULL CONSTRAINT DF_gen_salesmanUseRights_CanQuotation DEFAULT (1),
        CanCRN BIT NOT NULL CONSTRAINT DF_gen_salesmanUseRights_CanCRN DEFAULT (1),
        CanMySalesHistory BIT NOT NULL CONSTRAINT DF_gen_salesmanUseRights_CanMySalesHistory DEFAULT (1),
        CanCustomerCreate BIT NOT NULL CONSTRAINT DF_gen_salesmanUseRights_CanCustomerCreate DEFAULT (1),
        CanCustomerLocations BIT NOT NULL CONSTRAINT DF_gen_salesmanUseRights_CanCustomerLocations DEFAULT (1),
        CanLeaderboard BIT NOT NULL CONSTRAINT DF_gen_salesmanUseRights_CanLeaderboard DEFAULT (1),
        CanStockReports BIT NOT NULL CONSTRAINT DF_gen_salesmanUseRights_CanStockReports DEFAULT (0),
        CanReceipts BIT NOT NULL CONSTRAINT DF_gen_salesmanUseRights_CanReceipts DEFAULT (0),
        Created_User NVARCHAR(50) NULL,
        Created_Date DATETIME2 NOT NULL CONSTRAINT DF_gen_salesmanUseRights_Created_Date DEFAULT (GETDATE()),
        Edited_User NVARCHAR(50) NULL,
        Edited_Date DATETIME2 NULL
      );

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_salesmanUseRights') AND name = 'CanAdminSalesmanLocationHistory')
        ALTER TABLE gen_salesmanUseRights ADD CanAdminSalesmanLocationHistory BIT NOT NULL CONSTRAINT DF_gen_salesmanUseRights_CanAdminSalesmanLocationHistory DEFAULT (1);

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_salesmanUseRights') AND name = 'CanAdminUserCreation')
        ALTER TABLE gen_salesmanUseRights ADD CanAdminUserCreation BIT NOT NULL CONSTRAINT DF_gen_salesmanUseRights_CanAdminUserCreation DEFAULT (1);

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_salesmanUseRights') AND name = 'CanAdminSalesAndHistory')
        ALTER TABLE gen_salesmanUseRights ADD CanAdminSalesAndHistory BIT NOT NULL CONSTRAINT DF_gen_salesmanUseRights_CanAdminSalesAndHistory DEFAULT (1);

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_salesmanUseRights') AND name = 'CanAdminLocationTracking')
        ALTER TABLE gen_salesmanUseRights ADD CanAdminLocationTracking BIT NOT NULL CONSTRAINT DF_gen_salesmanUseRights_CanAdminLocationTracking DEFAULT (1);

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_salesmanUseRights') AND name = 'CanAdminCurrentSale')
        ALTER TABLE gen_salesmanUseRights ADD CanAdminCurrentSale BIT NOT NULL CONSTRAINT DF_gen_salesmanUseRights_CanAdminCurrentSale DEFAULT (1);

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_salesmanUseRights') AND name = 'isReporting')
        ALTER TABLE gen_salesmanUseRights ADD isReporting BIT NOT NULL CONSTRAINT DF_gen_salesmanUseRights_isReporting DEFAULT (1);

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_salesmanUseRights') AND name = 'isAssignCustomers')
        ALTER TABLE gen_salesmanUseRights ADD isAssignCustomers BIT NOT NULL CONSTRAINT DF_gen_salesmanUseRights_isAssignCustomers DEFAULT (1);

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('gen_salesmanUseRights') AND name = 'isUserRights')
        ALTER TABLE gen_salesmanUseRights ADD isUserRights BIT NOT NULL CONSTRAINT DF_gen_salesmanUseRights_isUserRights DEFAULT (1);
    `);
    console.log('✅ Salesman use rights table ready');

    // 7. inv_invoiceheader Alterations
    await pool.request().query(`
      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('inv_invoiceheader') AND name = 'isPending')
        ALTER TABLE inv_invoiceheader ADD isPending BIT NULL;

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('inv_invoiceheader') AND name = 'isApproved')
        ALTER TABLE inv_invoiceheader ADD isApproved BIT NULL;

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('inv_invoiceheader') AND name = 'isReject')
        ALTER TABLE inv_invoiceheader ADD isReject BIT NULL;

      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('inv_invoiceheader') AND name = 'rejReason')
        ALTER TABLE inv_invoiceheader ADD rejReason NVARCHAR(MAX) NULL;
    `);
    console.log('✅ Invoice header approval columns ready');

    return true;
  } catch (error) {
    console.error('❌ Error initializing database schema:', error);
    return false;
  }
}

module.exports = {
  initializeDatabase
};
