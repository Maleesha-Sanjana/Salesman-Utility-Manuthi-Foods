-- =============================================

-- Create date: <2014.03.20>
-- Description:	<Sales Order Post Process>
-- =============================================

CREATE PROCEDURE [dbo].[inv_USp_SalesOrderPostProcess] 
(   @p_DocAction VARCHAR(2),      
    @p_CustomerCode VARCHAR(20),
    @p_CustomerName VARCHAR(50),
    @p_SalesmanCode VARCHAR(20),
    @p_Address VARCHAR(150),
    @p_Iid VARCHAR(5),
    @p_TempDocNo VARCHAR(20),
	@p_CreditPeriod INT,
    @p_OrgDocNo VARCHAR(20),	
	@p_DocumentDate DATETIME,
	@p_ExpecteDate DATETIME,
	@p_PoDate DATETIME,
    @p_LocaCode VARCHAR(5),
    @p_ManualNo VARCHAR(20),
    @p_Reference VARCHAR(30),
    @p_Remarks VARCHAR(100),  
    @p_GrossAmount DECIMAL(10,3),
    @p_DiscPer DECIMAL(10,3),
    @p_DiscAmount DECIMAL(10,3),
    @p_TaxPer DECIMAL(10,3),
    @p_TaxAmount DECIMAL(10,3),
    @p_NetAmount DECIMAL(10,3),	
    @p_CostCenter VARCHAR(10), 
    @p_OtherCharge DECIMAL(10,3),
    @p_Recall Bit,  
    @p_QuoRecall Bit,
    @p_Quotation VARCHAR(20),	
    @p_SaveDocNo VARCHAR(20),
    @p_SalesType VARCHAR(20),
    @p_PriceLevel VARCHAR(15),
    @p_RoudAmt DECIMAL(10,3),
	@p_Sheduled Bit,
	@p_Freght Bit,
    @p_OrderConfirm Bit,
 	@p_User_Name VARCHAR(50)

	      
)
AS
DECLARE
@INTCOUNT INT,
@NoOfZero INT,
@Prifix VARCHAR(5),
@SerialNo INT,
@idx int

BEGIN TRAN

IF (@p_DocAction = 'P')
BEGIN	


IF @p_Recall=1
	BEGIN
 
    DELETE FROM inv_invoiceheader WHERE DocumentNo=@p_SaveDocNo AND LocaCode=@p_LocaCode AND IID=@p_Iid AND CostCenter=@p_CostCenter AND StatusId=1
    DELETE FROM inv_invoicedetails WHERE DocumentNo=@p_SaveDocNo AND LocaCode=@p_LocaCode AND IID=@p_Iid AND CostCenter=@p_CostCenter  AND StatusId=1
	DELETE FROM inv_salesorderdetails WHERE  DocumentNo=@p_SaveDocNo

	END



		IF @p_QuoRecall=1
	BEGIN
 
    DELETE FROM inv_invoiceheader WHERE DocumentNo=@p_SaveDocNo AND LocaCode=@p_LocaCode AND IID=@p_Iid AND CostCenter=@p_CostCenter and StatusId=0
    DELETE FROM inv_invoicedetails WHERE DocumentNo=@p_SaveDocNo AND LocaCode=@p_LocaCode AND IID=@p_Iid AND CostCenter=@p_CostCenter  and StatusId=0


	END

	INSERT INTO inv_invoiceheader (DocumentNo, LocaCode, Iid, DocumentDate, CustomerCode,SalesmanCode, ManualNo, Reference, Remarks, CreditPeriod, GrossAmount, DiscPer, DiscAmount, TaxPer, TaxAmount, NetAmount, BalanceAmount, StatusId,CostCenter,JobNumber,OtherCharge,SalesType,PriceLevel,Quotation,Performer,Dispatch,TempCreditAmt,RoudAmt,ExpectDate,PoDate,Created_User)
			VALUES (@p_OrgDocNo, @p_LocaCode, @p_Iid, @p_DocumentDate, @p_CustomerCode,@p_SalesmanCode, @p_ManualNo, @p_Reference, @p_Remarks, @p_CreditPeriod, @p_GrossAmount, @p_DiscPer, @p_DiscAmount, @p_TaxPer, @p_TaxAmount, @p_NetAmount, @p_NetAmount, 1,@p_CostCenter,'',@p_OtherCharge,@p_SalesType,@p_PriceLevel,'','','',0,@p_RoudAmt,@p_ExpecteDate,@p_PoDate,@p_User_Name)

	INSERT INTO inv_invoicedetails (DocumentNo, Iid, LocaCode, DocumentDate, ProductCode, ProductDescription, Margin, Unit, PackSize, Qty,BQTY, FreeQty, CostPrice, UnitPrice, WholeSalePrice,BatchNo,ExpiryDate, DiscPer, DiscAmount, Amount, StockLoca, Tax, StatusId,CostCenter,Created_User)
			SELECT @p_OrgDocNo, @p_Iid, @p_LocaCode, @p_DocumentDate, ProductCode, ProductDescription, Margin, Unit, PackSize, Qty,Qty, FreeQty, CostPrice, UnitPrice, WholeSalePrice,BatchNo,ExpiryDate,DiscPer, DiscAmount, Amount, StockLoca, Tax, 1,@p_CostCenter,@p_User_Name  FROM inv_temptransaction WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND Iid = @p_Iid
   

  

  IF @p_CustomerCode='D001'
     BEGIN
     INSERT INTO inv_customerinfo(CustomerCode,CustomerName,DocNo,Iid,LocaCode,CostCenter,DocumentDate,Address)
     VALUES(@p_CustomerCode,@p_CustomerName,@p_OrgDocNo,@p_Iid,@p_LocaCode,@p_CostCenter,@p_DocumentDate,@p_Address)
   
     END 	
	INSERT INTO inv_documentdetails(DocumentNo, Description, Amount, LocaCode, RefDocNo, Created_User)
			VALUES (@p_OrgDocNo, 'SALES ORDER SAVE', @p_NetAmount, @p_LocaCode, @p_TempDocNo, @p_User_Name)
 
	IF (@p_QuoRecall=1 or @p_Recall=0)
	BEGIN
	UPDATE gen_documentno SET orgdocumentno = orgdocumentno + 1 WHERE TransactionId = @p_Iid AND LocaCode = @p_LocaCode AND Costcenter = @p_Costcenter
	end
	-------------------------------Tax Detials Update
  INSERT INTO inv_grntaxdetails(DocumentNo,Tax,Amount,Loca,iid,GroupId,CostCenter) SELECT @p_OrgDocNo,Tax,Amount,Loca,iid,GroupId,@p_CostCenter FROM gen_temptaxdetails WHERE TempDocno=@p_TempDocNo and Loca=@p_Locacode and Iid=@p_Iid


	-------------------------------Discount Detials Update
   INSERT INTO inv_transdiscount(DocumentNo,LocaCode,CostCenter,Code,Name,Perc,Amount,Iid) SELECT @p_OrgDocNo,@p_LocaCode,@p_CostCenter,Code,Name,Perc,Amount,Iid FROM inv_tempdiscount WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND CostCenter = @p_CostCenter AND Iid = @p_Iid 


   INSERT INTO inv_salesorderdetails(DocumentNo,LocaCode,CostCenter,ProductCode,Colour,Size,Qty) SELECT @p_OrgDocNo,@p_LocaCode,@p_CostCenter,ProductCode,Colour,Size,Qty FROM inv_tempsalesorderdetails WHERE DocumentNo = @p_TempDocNo  
	-------------------------------FIFO Update

	DELETE FROM inv_temptransaction WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND Iid = @p_Iid
    DELETE FROM gen_temptaxdetails WHERE TempDocno=@p_TempDocNo and Loca=@p_Locacode and Iid=@p_Iid
  	DELETE FROM inv_tempdiscount WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND CostCenter = @p_CostCenter AND Iid = @p_Iid 

	
	
	
	IF @p_QuoRecall=1
	BEGIN
	UPDATE inv_invoiceheader SET Recall='True' WHERE DocumentNo=@p_Quotation AND LocaCode=@p_LocaCode AND IID='QUO' AND CostCenter=@p_CostCenter AND StatusId=1 AND Recall='False'
	UPDATE inv_invoicedetails SET Recall='True' WHERE DocumentNo=@p_Quotation AND LocaCode=@p_LocaCode AND IID='QUO' AND CostCenter=@p_CostCenter AND StatusId=1 AND Recall='False'
	END

END


IF (@p_DocAction = 'S')
BEGIN	

	INSERT INTO inv_invoiceheader (DocumentNo, LocaCode, Iid, DocumentDate, CustomerCode,SalesmanCode, ManualNo, Reference, Remarks, CreditPeriod, GrossAmount, DiscPer, DiscAmount, TaxPer, TaxAmount, NetAmount, BalanceAmount, StatusId,CostCenter,JobNumber,OtherCharge,SalesType,PriceLevel,Quotation,Performer,Dispatch,TempCreditAmt,RoudAmt,ExpectDate,PoDate,Created_User)
			VALUES (@p_OrgDocNo, @p_LocaCode, @p_Iid, @p_DocumentDate, @p_CustomerCode,@p_SalesmanCode, @p_ManualNo, @p_Reference, @p_Remarks, 0, @p_GrossAmount, @p_DiscPer, @p_DiscAmount, @p_TaxPer, @p_TaxAmount, @p_NetAmount, @p_NetAmount, 0,@p_CostCenter,'',@p_OtherCharge,@p_SalesType,@p_PriceLevel,'','','',0,@p_RoudAmt,@p_ExpecteDate,@p_PoDate,@p_User_Name)

	INSERT INTO inv_invoicedetails (DocumentNo, Iid, LocaCode, DocumentDate, ProductCode, ProductDescription, Margin, Unit, PackSize, Qty, FreeQty, CostPrice, UnitPrice, WholeSalePrice,BatchNo,ExpiryDate, DiscPer, DiscAmount, Amount, StockLoca, Tax, StatusId,CostCenter,Created_User)
			SELECT @p_OrgDocNo, @p_Iid, @p_LocaCode, @p_DocumentDate, ProductCode, ProductDescription, Margin, Unit, PackSize, Qty, FreeQty, CostPrice, UnitPrice, WholeSalePrice,BatchNo,ExpiryDate,DiscPer, DiscAmount, Amount, StockLoca, Tax, 0,@p_CostCenter,@p_User_Name  FROM inv_temptransaction WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND Iid = @p_Iid
   

	UPDATE gen_documentno SET savedocumentno = savedocumentno + 1 WHERE TransactionId = @p_Iid AND LocaCode = @p_LocaCode AND Costcenter = @p_Costcenter
	
	INSERT INTO inv_documentdetails(DocumentNo, Description, Amount, LocaCode, RefDocNo, Created_User)
			VALUES (@p_OrgDocNo, 'SALES ORDER SAVE', @p_NetAmount, @p_LocaCode, @p_TempDocNo, @p_User_Name)

   INSERT INTO inv_grnsavetaxdetails(DocumentNo,Tax,Amount,Loca,iid,GroupId) SELECT @p_OrgDocNo,Tax,Amount,Loca,iid,GroupId FROM gen_temptaxdetails WHERE TempDocno=@p_TempDocNo and Loca=@p_Locacode and Iid=@p_Iid
   INSERT INTO inv_savetransdiscount(DocumentNo,LocaCode,CostCenter,Code,Name,Perc,Amount,Iid) SELECT @p_OrgDocNo,@p_LocaCode,@p_CostCenter,Code,Name,Perc,Amount,Iid FROM inv_tempdiscount WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND CostCenter = @p_CostCenter AND Iid = @p_Iid 

	DELETE FROM inv_temptransaction WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND Iid = @p_Iid
    DELETE FROM gen_temptaxdetails WHERE TempDocno=@p_TempDocNo and Loca=@p_Locacode and Iid=@p_Iid
  	DELETE FROM inv_tempdiscount WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND CostCenter = @p_CostCenter AND Iid = @p_Iid 

    IF @p_Recall=1
	BEGIN
 
    DELETE FROM inv_invoiceheader WHERE DocumentNo=@p_SaveDocNo AND LocaCode=@p_LocaCode AND IID=@p_Iid AND CostCenter=@p_CostCenter AND StatusId=0
    DELETE FROM inv_invoicedetails WHERE DocumentNo=@p_SaveDocNo AND LocaCode=@p_LocaCode AND IID=@p_Iid AND CostCenter=@p_CostCenter  AND StatusId=0

	END

END



IF @@ERROR<>0
	ROLLBACK TRAN
ELSE
	COMMIT TRAN
