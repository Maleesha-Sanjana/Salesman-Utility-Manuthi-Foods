-- Create date: <2014.01.16>
-- Description:	<InvoicePostProcess>
-- =============================================

CREATE PROCEDURE [dbo].[inv_USp_InvoicePostProcess] 
(   @p_DocAction VARCHAR(2),
    @p_CustomerCode VARCHAR(20),
    @p_CustomerName VARCHAR(50),
    @p_SalesmanCode VARCHAR(20),
    @p_Address VARCHAR(150),
    @p_Iid VARCHAR(5),
    @p_TempDocNo VARCHAR(20),
    @p_OrgDocNo VARCHAR(20),
    @p_TourCode	VARCHAR(20),
	@p_DocumentDate DATETIME,
    @p_LocaCode VARCHAR(5),
    @p_ManualNo VARCHAR(20),
    @p_Reference VARCHAR(30),
    
    @p_DeliveryTerms VARCHAR(20),
    @p_PaymentTerms VARCHAR(100),
    
    @p_Remarks VARCHAR(300),
    @p_CreditPeriod INT,
    @p_GrossAmount DECIMAL(10,3),
    @p_DiscPer DECIMAL(10,3),
    @p_DiscAmount DECIMAL(10,3),
    @p_TaxPer DECIMAL(10,3),
    @p_TaxAmount DECIMAL(10,3),
    @p_NetAmount DECIMAL(10,3),
	@p_LedgerCode1 VARCHAR(15),
    @p_DoubleEntery1 VARCHAR(5),
    @p_LedgerCode2 VARCHAR(15),
    @p_LedgerCode3 VARCHAR(15),
    @p_DoubleEntery2 VARCHAR(5),
    @p_DoubleEntery3 VARCHAR(5),
    @p_CostCenter VARCHAR(10),
    @p_JobNumber VARCHAR(10),
    @p_OtherCharge DECIMAL(10,3),
    @p_Recall Bit,
    @p_QuoRecall Bit,
    @p_SonRecall Bit,
    @p_DisRecall Bit,
    @p_ToDispach Bit,
    @p_SaveDocNo VARCHAR(20),
    @p_SalesType VARCHAR(20),
    @p_PriceLevel VARCHAR(15),
    @p_Quotation VARCHAR(20),
    @p_Performer VARCHAR(20),
    @p_Dispatch VARCHAR(20),
    @p_TempCreditAmt DECIMAL(10,3),
    @p_RoudAmt DECIMAL(10,3),
    @p_PODate DATETIME,   
    @p_Currancy VARCHAR(20),
 	@p_User_Name VARCHAR(50)
)
AS
DECLARE
@creditAmount float,
@creditLimit DECIMAL (18,3),
@cashAmount DECIMAL (18,3),
@otherAmount DECIMAL (18,3),
@DisOrgDocNo VARCHAR(20),
@LedgerCode VARCHAR(20),
@LedgerVat VARCHAR(20),
@LedgerOther VARCHAR(20),
@Tax VARCHAR(20),
@p_TaxAmt DECIMAL(10,3),
@creditPeriod INT,
@INTCOUNT INT,
@CreditLimitRes int,
@NoOfZero INT,
@Prifix VARCHAR(5),
@SerialNo INT,
@PaymentCode VARCHAR(20),
@credittot float,
@idx int,
@p_LedgerAcc VARCHAR(20),
@exchangeRate DECIMAL (10,3)


BEGIN TRAN

IF (@p_DocAction = 'P')
BEGIN	


 IF @p_Currancy<>'LKR'
 BEGIN
	INSERT INTO inv_invoiceheadermultycurrancy (DocumentNo, LocaCode, Iid, DocumentDate, CustomerCode,SalesmanCode, ManualNo, Reference, Remarks, CreditPeriod, GrossAmount, DiscPer, DiscAmount, TaxPer, TaxAmount, NetAmount, BalanceAmount, StatusId,CostCenter,JobNumber,OtherCharge,SalesType,PriceLevel,Quotation,Performer,Dispatch,TempCreditAmt,RoudAmt,TourCode,PoDate,Currancy,Created_User)
			VALUES (@p_OrgDocNo, @p_LocaCode, @p_Iid, @p_DocumentDate, @p_CustomerCode,@p_SalesmanCode, @p_ManualNo, @p_Reference, @p_Remarks, @p_CreditPeriod, @p_GrossAmount, @p_DiscPer, @p_DiscAmount, @p_TaxPer, @p_TaxAmount, @p_NetAmount, @p_NetAmount, 1,@p_CostCenter,@p_JobNumber,@p_OtherCharge,@p_SalesType,@p_PriceLevel,@p_Quotation,@p_Performer,@p_Dispatch,@p_TempCreditAmt,@p_RoudAmt,@p_TourCode,@p_PODate,@p_Currancy,@p_User_Name)

	INSERT INTO inv_invoicedetailsmultycurrancy (DocumentNo, Iid, LocaCode, DocumentDate, ProductCode, ProductDescription,LongDescription, Margin, Unit, PackSize, Qty,BQTY, FreeQty, CostPrice, UnitPrice, WholeSalePrice,BatchNo,ExpiryDate, DiscPer, DiscAmount, Amount, StockLoca, Tax, StatusId,RefCode,CostCenter,Created_User)
			SELECT @p_OrgDocNo, @p_Iid, @p_LocaCode, @p_DocumentDate, ProductCode, ProductDescription,LongDescription, Margin, Unit, PackSize, Qty,Qty, FreeQty, CostPrice, UnitPrice, WholeSalePrice,BatchNo,ExpiryDate,DiscPer, DiscAmount, Amount, StockLoca, Tax, 1,RefCode,@p_CostCenter,@p_User_Name  FROM inv_temptransaction WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND CostCenter = @p_CostCenter AND Iid = @p_Iid

     SELECT @exchangeRate=ISNULL(SUM(RunningCurrency), 0)  FROM gen_currency WHERE CurrencyCode =@p_Currancy   
     SET @p_GrossAmount=@p_GrossAmount*@exchangeRate
     SET @p_DiscAmount=@p_DiscAmount*@exchangeRate
     SET @p_TaxAmount=@p_TaxAmount*@exchangeRate
     SET @p_NetAmount=@p_NetAmount*@exchangeRate     
     SET @p_OtherCharge=@p_OtherCharge*@exchangeRate
     SET @p_RoudAmt=@p_RoudAmt*@exchangeRate     
     UPDATE inv_temptransaction SET UnitPrice=UnitPrice*@exchangeRate,DiscAmount=DiscAmount*@exchangeRate,Amount=Amount*@exchangeRate   WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND CostCenter = @p_CostCenter AND Iid = @p_Iid
 	 UPDATE inv_temppayment SET Amount=Amount*@exchangeRate   WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode 

 	
 END
 

   --Enable when price included vat 
  --   set @vat= @p_NetAmount-(@p_NetAmount)/1.15
  --set @nbt=(@p_NetAmount-@vat)-((@p_NetAmount)/1.15)*100/102
  --INSERT INTO gen_temptaxdetails(TempDocno,Tax,Amount,Loca,Iid,GroupId)VALUES(@p_TempDocNo,'VAT',@vat,@p_LocaCode,'INV','2')
  --INSERT INTO gen_temptaxdetails(TempDocno,Tax,Amount,Loca,Iid,GroupId)VALUES(@p_TempDocNo,'NBT',@nbt,@p_LocaCode,'INV','2')
  --set @p_TaxAmount=@vat+@nbt

     SELECT @creditAmount=ISNULL(SUM(Amount), 0)  FROM inv_temppayment WHERE Iid ='IRE'  AND TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND PaymentCode='006'
	INSERT INTO inv_invoiceheader (DocumentNo, LocaCode, Iid, DocumentDate, CustomerCode,SalesmanCode, ManualNo, Reference, Remarks, CreditPeriod, GrossAmount, DiscPer, DiscAmount, TaxPer, TaxAmount, NetAmount, BalanceAmount, StatusId,CostCenter,JobNumber,OtherCharge,SalesType,PriceLevel,Quotation,Performer,Dispatch,TempCreditAmt,RoudAmt,TourCode,PoDate,Currancy,PaymentTerms,Created_User)
			VALUES (@p_OrgDocNo, @p_LocaCode, @p_Iid, @p_DocumentDate, @p_CustomerCode,@p_SalesmanCode, @p_ManualNo, @p_Reference, @p_Remarks, @p_CreditPeriod, @p_GrossAmount, @p_DiscPer, @p_DiscAmount, @p_TaxPer, @p_TaxAmount, @p_NetAmount, @p_NetAmount, 1,@p_CostCenter,@p_JobNumber,@p_OtherCharge,@p_SalesType,@p_PriceLevel,@p_Quotation,@p_Performer,@p_Dispatch,@p_TempCreditAmt,@p_RoudAmt,@p_TourCode,@p_PODate,@p_Currancy,@p_PaymentTerms,@p_User_Name)

	INSERT INTO inv_invoicedetails (DocumentNo, Iid, LocaCode, DocumentDate, ProductCode, ProductDescription,LongDescription, Margin, Unit, PackSize, Qty,BQTY, FreeQty, CostPrice, UnitPrice, WholeSalePrice,BatchNo,ExpiryDate, DiscPer, DiscAmount, Amount, StockLoca, Tax, StatusId,RefCode,CostCenter,Created_User)
			SELECT @p_OrgDocNo, @p_Iid, @p_LocaCode, @p_DocumentDate, ProductCode, ProductDescription,LongDescription, Margin, Unit, PackSize, Qty,Qty, FreeQty, CostPrice, UnitPrice, WholeSalePrice,BatchNo,ExpiryDate,DiscPer, DiscAmount, Amount, StockLoca, Tax, 1,RefCode,@p_CostCenter,@p_User_Name  FROM inv_temptransaction WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND CostCenter = @p_CostCenter AND Iid = @p_Iid
   
         INSERT INTO inv_invoicedetailscoloursize(DocumentNo,LocaCode,CostCenter,ProductCode,Colour,Size,Qty) SELECT @p_OrgDocNo,@p_LocaCode,@p_CostCenter,ProductCode,Colour,Size,Qty FROM inv_tempsalesorderdetails WHERE DocumentNo = @p_TempDocNo  

  IF @p_CustomerCode='D001' or @p_DisRecall='True'
     BEGIN
     INSERT INTO inv_customerinfo(CustomerCode,CustomerName,DocNo,Iid,LocaCode,CostCenter,DocumentDate,Address)
     VALUES(@p_CustomerCode,@p_CustomerName,@p_OrgDocNo,@p_Iid,@p_LocaCode,@p_CostCenter,@p_DocumentDate,@p_Address)
     
     END
     
     --IF @p_TempCreditAmt>0
     --BEGIN
     --SELECT @creditAmount=ISNULL(SUM(Amount), 0)  FROM inv_temppayment WHERE Iid ='IRE'  AND TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND PaymentCode='006'
     --SELECT @creditLimit=CreditLimit,@CreditLimitRes=CreditLimitRestrict FROM gen_customer WHERE CustomerCode=@p_CustomerCode
     --SET @credittot=@creditLimit-@creditAmount                     
                      
     --IF @credittot<0 and @CreditLimitRes=1
     --BEGIN
     --UPDATE gen_customer SET TemporaryCredit=TemporaryCredit+@credittot WHERE CustomerCode=@p_CustomerCode      
   --UPDATE gen_customer SET CreditLimit=CreditLimit-@creditAmount+ABS(@credittot) WHERE CustomerCode=@p_CustomerCode
     --END      
         
     --if @credittot>0 and @CreditLimitRes=1
     --BEGIN          
     --UPDATE gen_customer SET CreditLimit=CreditLimit-@creditAmount WHERE CustomerCode=@p_CustomerCode
     --END         
         
     
     
  IF @p_ToDispach='True'
     BEGIN
     
     
   SELECT @DisOrgDocNo=orgdocumentno,@Prifix=Prifix FROM gen_documentno WHERE TransactionId = 'DIP' AND LocaCode = @p_LocaCode AND Costcenter = @p_Costcenter
   SET @NoOfZero=LEN(11-@DisOrgDocNo)
   SET @DisOrgDocNo=ltrim(rtrim(@p_LocaCode)) + ltrim(rtrim(@Prifix)) + REPLICATE(0,@NoOfZero+3)+ @DisOrgDocNo

     
     
     	INSERT INTO inv_invoiceheader (DocumentNo,InvNo,LocaCode, Iid, DocumentDate, CustomerCode,SalesmanCode, ManualNo, Reference, Remarks, NetAmount, BalanceAmount, StatusId,CostCenter,Created_User)
			VALUES (@DisOrgDocNo,@p_OrgDocNo,@p_LocaCode, 'DIP', @p_DocumentDate, @p_CustomerCode,@p_SalesmanCode, @p_ManualNo, @p_Reference, @p_Remarks, @p_NetAmount, 0, 0,@p_CostCenter,@p_User_Name)

		INSERT INTO inv_invoicedetails (DocumentNo,InvNo, Iid, LocaCode, DocumentDate, ProductCode, ProductDescription,LongDescription, Margin, Unit, PackSize, Qty,BQty, FreeQty, CostPrice, UnitPrice, WholeSalePrice,BatchNo, Amount, StockLoca, Tax, StatusId,CostCenter,Created_User)
			SELECT @DisOrgDocNo,@p_OrgDocNo, 'DIP', @p_LocaCode, @p_DocumentDate, ProductCode, ProductDescription,LongDescription, Margin, Unit, PackSize, Qty,Qty, FreeQty, CostPrice, UnitPrice, WholeSalePrice,BatchNo, Amount, StockLoca, Tax, 0,@p_CostCenter,@p_User_Name  FROM inv_temptransaction WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND Iid = @p_Iid
   	UPDATE gen_documentno SET orgdocumentno = orgdocumentno + 1 WHERE TransactionId = 'DIP' AND LocaCode = @p_LocaCode AND Costcenter = @p_Costcenter

    END




-------------------/////////////////////////
	SELECT @creditAmount = ISNULL(SUM(Amount), 0) FROM inv_temppayment WHERE PaymentCode = '006' AND TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode
	SELECT @creditPeriod = CreditPeriod FROM inv_temppayment WHERE PaymentCode = '006' AND TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode
	SELECT @cashAmount = ISNULL(SUM(Amount), 0) FROM inv_temppayment WHERE PaymentCode = '001' AND TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode
  	SELECT @otherAmount = ISNULL(SUM(Amount), 0) FROM inv_temppayment WHERE PaymentCode <> '006' AND TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode
  
   SELECT @DisOrgDocNo=orgdocumentno,@Prifix=Prifix FROM gen_documentno WHERE TransactionId = 'REC' AND LocaCode = @p_LocaCode AND Costcenter = @p_Costcenter
   SET @NoOfZero=LEN(11-@DisOrgDocNo)
   SET @DisOrgDocNo=ltrim(rtrim(@p_LocaCode)) + ltrim(rtrim(@Prifix)) + REPLICATE(0,@NoOfZero+3)+ @DisOrgDocNo 


   
IF  @otherAmount>0
  begin
  SELECT @DisOrgDocNo=orgdocumentno,@Prifix=Prifix FROM gen_documentno WHERE TransactionId = 'REC' AND LocaCode = @p_LocaCode AND Costcenter = @p_Costcenter
   SET @NoOfZero=LEN(2-@DisOrgDocNo)
   SET @DisOrgDocNo=ltrim(rtrim(@p_LocaCode)) + ltrim(rtrim(@Prifix)) + REPLICATE(0,@NoOfZero-1)+ @DisOrgDocNo 
   UPDATE gen_documentno SET orgdocumentno = orgdocumentno + 1 WHERE TransactionId = 'REC' AND LocaCode = @p_LocaCode AND Costcenter = @p_Costcenter


     INSERT INTO inv_paymentheader(DocumentNo, RefDocNo, LocaCode, Iid, RefIid, DocumentDate, CustomerCode, Description,SalesmanCode, Reference, Remarks, Amount, BalanceAmount,Tid,CostCenter,TourCode, Created_User)
              VALUES(@DisOrgDocNo, @p_OrgDocNo, @p_LocaCode, 'REC', @p_Iid, @p_DocumentDate, @p_CustomerCode,@p_CustomerName, @p_SalesmanCode, @p_Reference, @p_Remarks, @otherAmount, @creditAmount,0,@p_CostCenter,@p_TourCode,@p_User_Name)
	
	INSERT INTO inv_paymentdetails (DocumentNo, CustomerCode, Iid, RefIid, RefDocNo, LocaCode, PaymentDate, PaymentCode, Amount, BalanceAmount, CardChequeNo, CurrencyCode, CreditPeriod, BankCode, BranchCode,BankName, BranchName, ChequeDate, ChequePrinted, ChequeStatus,Tid, IsCancelled,TerminalID,CostCenter, Created_User)
		SELECT @DisOrgDocNo, @p_CustomerCode, 'REC', @p_Iid, @p_OrgDocNo, @p_LocaCode, @p_DocumentDate, PaymentCode, Amount, (CASE PaymentCode WHEN '006' THEN Amount ELSE 0 END), CardChequeNo, CurrencyCode, @p_CreditPeriod, BankCode, BranchCode,BankName, BranchName, ChequeDate, 0, 0,0, 0,TerminalID,@p_CostCenter,@p_User_Name FROM inv_temppayment WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND (Iid = 'IRE' or Iid = 'OVP') and PaymentCode <> '006'


  END




   IF  @creditAmount>0
  begin
 
   SELECT @DisOrgDocNo=orgdocumentno,@Prifix=Prifix FROM gen_documentno WHERE TransactionId = 'RECI' AND LocaCode = @p_LocaCode AND Costcenter = @p_Costcenter
   SET @NoOfZero=LEN(2-@DisOrgDocNo)
   SET @DisOrgDocNo=ltrim(rtrim(@p_LocaCode)) + ltrim(rtrim(@Prifix)) + REPLICATE(0,@NoOfZero)+ @DisOrgDocNo 
   UPDATE gen_documentno SET orgdocumentno = orgdocumentno + 1 WHERE TransactionId = 'RECI' AND LocaCode = @p_LocaCode AND Costcenter = @p_Costcenter


     INSERT INTO inv_paymentheader(DocumentNo, RefDocNo, LocaCode, Iid, RefIid, DocumentDate, CustomerCode, Description,SalesmanCode, Reference, Remarks, Amount, BalanceAmount,Tid,CostCenter,TourCode, Created_User)
              VALUES(@DisOrgDocNo, @p_OrgDocNo, @p_LocaCode, 'REC', @p_Iid, @p_DocumentDate, @p_CustomerCode,@p_CustomerName, @p_SalesmanCode, @p_Reference, @p_Remarks, @creditAmount, @creditAmount,0,@p_CostCenter,@p_TourCode,@p_User_Name)
	
	INSERT INTO inv_paymentdetails (DocumentNo, CustomerCode, Iid, RefIid, RefDocNo, LocaCode, PaymentDate, PaymentCode, Amount, BalanceAmount, CardChequeNo, CurrencyCode, CreditPeriod, BankCode, BranchCode,BankName, BranchName, ChequeDate, ChequePrinted, ChequeStatus,Tid, IsCancelled,TerminalID,CostCenter, Created_User)
		SELECT @DisOrgDocNo, @p_CustomerCode, 'REC', @p_Iid, @p_OrgDocNo, @p_LocaCode, @p_DocumentDate, PaymentCode, Amount, (CASE PaymentCode WHEN '006' THEN Amount ELSE 0 END), CardChequeNo, CurrencyCode, @p_CreditPeriod, BankCode, BranchCode,BankName, BranchName, ChequeDate, 0, 0,0, 0,TerminalID,@p_CostCenter,@p_User_Name FROM inv_temppayment WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND (Iid = 'IRE' or Iid = 'OVP') and PaymentCode = '006'

  END



--IF  @creditAmount=0
--  begin
--  SELECT @DisOrgDocNo=orgdocumentno,@Prifix=Prifix FROM gen_documentno WHERE TransactionId = 'REC' AND LocaCode = @p_LocaCode AND Costcenter = @p_Costcenter
--   SET @NoOfZero=LEN(2-@DisOrgDocNo)
--   SET @DisOrgDocNo=ltrim(rtrim(@p_LocaCode)) + ltrim(rtrim(@Prifix)) + REPLICATE(0,@NoOfZero-1)+ @DisOrgDocNo 
--   UPDATE gen_documentno SET orgdocumentno = orgdocumentno + 1 WHERE TransactionId = 'REC' AND LocaCode = @p_LocaCode AND Costcenter = @p_Costcenter

--  END
--   ELSE
--   BEGIN
--   SELECT @DisOrgDocNo=orgdocumentno,@Prifix=Prifix FROM gen_documentno WHERE TransactionId = 'RECI' AND LocaCode = @p_LocaCode AND Costcenter = @p_Costcenter
--   SET @NoOfZero=LEN(2-@DisOrgDocNo)
--   SET @DisOrgDocNo=ltrim(rtrim(@p_LocaCode)) + ltrim(rtrim(@Prifix)) + REPLICATE(0,@NoOfZero)+ @DisOrgDocNo 
--   UPDATE gen_documentno SET orgdocumentno = orgdocumentno + 1 WHERE TransactionId = 'RECI' AND LocaCode = @p_LocaCode AND Costcenter = @p_Costcenter

--   END


--    INSERT INTO inv_paymentheader(DocumentNo, RefDocNo, LocaCode, Iid, RefIid, DocumentDate, CustomerCode, Description,SalesmanCode, Reference, Remarks, Amount, BalanceAmount,Tid,CostCenter,TourCode, Created_User)
--              VALUES(@DisOrgDocNo, @p_OrgDocNo, @p_LocaCode, 'REC', @p_Iid, @p_DocumentDate, @p_CustomerCode,@p_CustomerName, @p_SalesmanCode, @p_Reference, @p_Remarks, @p_NetAmount, @creditAmount,0,@p_CostCenter,@p_TourCode,@p_User_Name)
	
--	INSERT INTO inv_paymentdetails (DocumentNo, CustomerCode, Iid, RefIid, RefDocNo, LocaCode, PaymentDate, PaymentCode, Amount, BalanceAmount, CardChequeNo, CurrencyCode, CreditPeriod, BankCode, BranchCode,BankName, BranchName, ChequeDate, ChequePrinted, ChequeStatus,Tid, IsCancelled,TerminalID,CostCenter, Created_User)
--		SELECT @DisOrgDocNo, @p_CustomerCode, 'REC', @p_Iid, @p_OrgDocNo, @p_LocaCode, @p_DocumentDate, PaymentCode, Amount, (CASE PaymentCode WHEN '006' THEN Amount ELSE 0 END), CardChequeNo, CurrencyCode, @p_CreditPeriod, BankCode, BranchCode,BankName, BranchName, ChequeDate, 0, 0,0, 0,TerminalID,@p_CostCenter,@p_User_Name FROM inv_temppayment WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND (Iid = 'IRE' or Iid = 'OVP')

--   --	UPDATE gen_documentno SET orgdocumentno = orgdocumentno + 1 WHERE TransactionId = 'REC' AND LocaCode = @p_LocaCode AND Costcenter = @p_Costcenter




	--Change by Jayan on 22/07/2012	and above statement Tid 0 Update

	INSERT INTO inv_paymentdocdetails (DocumentNo, AccCode, Iid,PaidDocumentNo,LocaCode, PaymentDate,Amount,TYPE,Tid,CostCenter,ManualNo,RefNo,Created_User)
		SELECT @p_OrgDocNo, @p_CustomerCode, 'OVP', @p_OrgDocNo, @p_LocaCode, @p_DocumentDate,Amount,3,0,@p_CostCenter,@p_ManualNo,@p_Reference,@p_User_Name FROM inv_temppayment WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND Iid = 'OVP'


	IF  @creditAmount>0
    BEGIN
	INSERT INTO inv_paymentdocdetails (DocumentNo, AccCode, Iid,LocaCode,PaidDocumentNo, PaymentDate,CreditPeriod,Amount,BalanceAmount,type,Tid,CostCenter,ManualNo,RefNo,Created_User)
              VALUES(@p_OrgDocNo, @p_CustomerCode,@p_Iid, @p_LocaCode, @p_OrgDocNo, @p_DocumentDate,@p_CreditPeriod,@creditAmount,@creditAmount,0,0,@p_CostCenter,@p_ManualNo,@p_Reference,@p_User_Name) 
    END 


--////////////

		DECLARE serialUpdate CURSOR FOR 
		select LedgerCode1,PaymentCode FROM inv_temppayment WHERE inv_temppayment.TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode and (inv_temppayment.IID='IRE')

		OPEN serialUpdate
		FETCH NEXT FROM serialUpdate INTO @LedgerCode,@PaymentCode

		WHILE @@FETCH_STATUS = 0
		BEGIN
		SET @SerialNo=''	
		SELECT @SerialNo = DrDocumentNo FROM acc_documentno WHERE LederCode = @LedgerCode 
	 --   SELECT @SerialNo = MAX(SerialNO) +1  FROM inv_temppayment WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode and LedgerCode1=@p_LedgerCode1
		
		UPDATE inv_temppayment SET serialno=@SerialNo FROM inv_temppayment WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode and LedgerCode1=@LedgerCode and PaymentCode=@PaymentCode
		UPDATE acc_documentno SET  DrDocumentNo = DrDocumentNo + 1 WHERE LederCode = @LedgerCode
		
		FETCH NEXT FROM serialUpdate INTO @LedgerCode,@PaymentCode
		END

		CLOSE serialUpdate
		DEALLOCATE serialUpdate	


--TaxAmount=0 and OtherCharge=0
	IF @p_TaxAmount=0 and @p_OtherCharge=0
	BEGIN
		INSERT INTO acc_gltrans(DocNo,Serialno,Loca,Iid,LedgerAcc,DoubleEntery,Amount,CostCenter,DocumentDate,Created_User) SELECT @DisOrgDocNo,serialno,@p_LocaCode,@p_Iid,LedgerCode2,DoubleEntery2,Amount,@p_CostCenter,@p_DocumentDate,@p_User_Name FROM inv_temppayment WHERE inv_temppayment.TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode and (inv_temppayment.IID='IRE' or inv_temppayment.IID='OVP')
		INSERT INTO acc_gltrans(DocNo,Serialno,Loca,Iid,LedgerAcc,DoubleEntery,Amount,CostCenter,DocumentDate,Created_User) SELECT  @DisOrgDocNo,serialno,@p_LocaCode,@p_Iid,LedgerCode1,DoubleEntery1,Amount,@p_CostCenter,@p_DocumentDate,@p_User_Name FROM inv_temppayment WHERE inv_temppayment.TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode and (inv_temppayment.IID='IRE' or inv_temppayment.IID='OVP')
	END   
	
		 	UPDATE ad SET  ad.DrDocumentNo = ad.DrDocumentNo + 1 from acc_documentno ad INNER JOIN inv_temppayment tp on ad.LederCode=tp.PaymentCode  WHERE ad.LederCode = '011' and tp.TempDocNo = @p_TempDocNo AND tp.LocaCode = @p_LocaCode AND tp.PaymentCode='011' and len(tp.CardChequeNo)<>6 
--if @p_TaxAmount>0 and @p_OtherCharge=0

   IF @p_TaxAmount>0 and @p_OtherCharge=0
    BEGIN    
       
      
    INSERT INTO acc_gltrans(DocNo,Serialno,Loca,Iid,LedgerAcc,DoubleEntery,Amount,CostCenter,DocumentDate,Created_User) SELECT @DisOrgDocNo,serialno,@p_LocaCode,@p_Iid,LedgerCode2,DoubleEntery2,Amount,@p_CostCenter,@p_DocumentDate,@p_User_Name FROM inv_temppayment WHERE inv_temppayment.TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode and (inv_temppayment.IID='IRE' or inv_temppayment.IID='OVP')
    INSERT INTO acc_gltrans(DocNo,Serialno,Loca,Iid,LedgerAcc,DoubleEntery,Amount,CostCenter,DocumentDate,Created_User) SELECT  @DisOrgDocNo,serialno,@p_LocaCode,@p_Iid,LedgerCode1,DoubleEntery1,Amount,@p_CostCenter,@p_DocumentDate,@p_User_Name FROM inv_temppayment WHERE inv_temppayment.TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode and (inv_temppayment.IID='IRE' or inv_temppayment.IID='OVP')
   
      	DECLARE taxUpdateLeg CURSOR FOR 
        SELECT Tax,Amount FROM gen_temptaxdetails WHERE TempDocno=@p_TempDocNo and Loca=@p_Locacode and Iid=@p_Iid
---------------------
		OPEN taxUpdateLeg
		FETCH NEXT FROM taxUpdateLeg INTO @Tax,@p_TaxAmt
		WHILE @@FETCH_STATUS = 0
		BEGIN
      
       IF @Tax='VAT'
       BEGIN
       SELECT @LedgerVat=LedgerCode FROM acc_transactiontype WHERE Transtype='VATP'  
       END
       IF @Tax='NBT'
       BEGIN
       SELECT @LedgerVat=LedgerCode FROM acc_transactiontype WHERE Transtype='NBTP'  
       END
   
      ----------------------
		DECLARE taxUpdate CURSOR FOR 
	    SELECT LedgerAcc,IDX FROM acc_gltrans WHERE acc_gltrans.DocNo=@DisOrgDocNo AND acc_gltrans.CostCenter=@p_CostCenter and LedgerAcc=@p_LedgerCode1

		OPEN taxUpdate
		FETCH NEXT FROM taxUpdate INTO @p_LedgerAcc,@idx
		WHILE @@FETCH_STATUS = 0
		BEGIN
	
		UPDATE acc_gltrans SET acc_gltrans.Amount=acc_gltrans.Amount-@p_TaxAmt FROM acc_gltrans WHERE acc_gltrans.DocNo=@DisOrgDocNo AND acc_gltrans.CostCenter=@p_CostCenter and LedgerAcc=@p_LedgerAcc and IDX=@idx
        BREAK
	   ---------------------	

		FETCH NEXT FROM taxUpdate INTO @p_LedgerAcc,@idx
		END
		CLOSE taxUpdate
		DEALLOCATE taxUpdate	    
      -----------------
 	    INSERT INTO acc_gltrans(DocNo,Loca,Iid,LedgerAcc,DoubleEntery,Amount,CostCenter,DocumentDate,Created_User) VALUES(@DisOrgDocNo,@p_LocaCode,@p_Iid,@LedgerVat,'CR',@p_TaxAmt,@p_CostCenter,@p_DocumentDate,@p_User_Name) 

       FETCH NEXT FROM taxUpdateLeg INTO @Tax,@p_TaxAmt
		END
		CLOSE taxUpdateLeg
		DEALLOCATE taxUpdateLeg	    
  ---------------------

    END
 ------------------------
 
 --if @p_TaxAmount>0 and @p_OtherCharge>0    
      IF @p_TaxAmount>0 and @p_OtherCharge>0
    BEGIN      
    INSERT INTO acc_gltrans(DocNo,Serialno,Loca,Iid,LedgerAcc,DoubleEntery,Amount,CostCenter,DocumentDate,Created_User) SELECT @DisOrgDocNo,serialno,@p_LocaCode,@p_Iid,LedgerCode2,DoubleEntery2,Amount,@p_CostCenter,@p_DocumentDate,@p_User_Name FROM inv_temppayment WHERE inv_temppayment.TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode and (inv_temppayment.IID='IRE' or inv_temppayment.IID='OVP')
    INSERT INTO acc_gltrans(DocNo,Serialno,Loca,Iid,LedgerAcc,DoubleEntery,Amount,CostCenter,DocumentDate,Created_User) SELECT  @DisOrgDocNo,serialno,@p_LocaCode,@p_Iid,LedgerCode1,DoubleEntery1,Amount,@p_CostCenter,@p_DocumentDate,@p_User_Name FROM inv_temppayment WHERE inv_temppayment.TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode and (inv_temppayment.IID='IRE' or inv_temppayment.IID='OVP')
    
     --SELECT @LedgerVat=LedgerCode FROM acc_transactiontype WHERE Transtype='VATP'  
     SELECT @LedgerOther=LedgerCode FROM acc_transactiontype WHERE Transtype='OTHR'     
   
   		DECLARE taxUpdate CURSOR FOR 
	    SELECT LedgerAcc,IDX FROM acc_gltrans WHERE acc_gltrans.DocNo=@p_OrgDocNo AND acc_gltrans.CostCenter=@p_CostCenter and LedgerAcc=@p_LedgerCode1

		OPEN taxUpdate
		FETCH NEXT FROM taxUpdate INTO @p_LedgerAcc,@idx
		WHILE @@FETCH_STATUS = 0
		BEGIN
		UPDATE acc_gltrans SET acc_gltrans.Amount=acc_gltrans.Amount-@p_OtherCharge FROM acc_gltrans WHERE acc_gltrans.DocNo=@DisOrgDocNo AND acc_gltrans.CostCenter=@p_CostCenter and LedgerAcc=@p_LedgerAcc and IDX=@idx
		--UPDATE acc_gltrans SET acc_gltrans.Amount=acc_gltrans.Amount-@p_TaxAmount-@p_OtherCharge FROM acc_gltrans WHERE acc_gltrans.DocNo=@p_OrgDocNo AND acc_gltrans.CostCenter=@p_CostCenter and LedgerAcc=@p_LedgerAcc and IDX=@idx
        BREAK
		
		FETCH NEXT FROM taxUpdate INTO @p_LedgerAcc,@idx
		END
		CLOSE taxUpdate
		DEALLOCATE taxUpdate	   
   
    --INSERT INTO acc_gltrans(DocNo,Loca,Iid,LedgerAcc,DoubleEntery,Amount,CostCenter,DocumentDate,Created_User) VALUES(@p_OrgDocNo,@p_LocaCode,@p_Iid,@LedgerVat,'CR',@p_TaxAmount,@p_CostCenter,@p_DocumentDate,@p_User_Name) 
    INSERT INTO acc_gltrans(DocNo,Loca,Iid,LedgerAcc,DoubleEntery,Amount,CostCenter,DocumentDate,Created_User) VALUES(@DisOrgDocNo,@p_LocaCode,@p_Iid,@LedgerOther,'CR',@p_OtherCharge,@p_CostCenter,@p_DocumentDate,@p_User_Name) 


      	DECLARE taxUpdateLeg CURSOR FOR 
        SELECT Tax,Amount FROM gen_temptaxdetails WHERE TempDocno=@p_TempDocNo and Loca=@p_Locacode and Iid=@p_Iid
---------------------
		OPEN taxUpdateLeg
		FETCH NEXT FROM taxUpdateLeg INTO @Tax,@p_TaxAmt
		WHILE @@FETCH_STATUS = 0
		BEGIN
      
       IF @Tax='VAT'
       BEGIN
       SELECT @LedgerVat=LedgerCode FROM acc_transactiontype WHERE Transtype='VATP'  
       END
       IF @Tax='NBT'
       BEGIN
       SELECT @LedgerVat=LedgerCode FROM acc_transactiontype WHERE Transtype='NBTP'  
       END
   
      ----------------------
		DECLARE taxUpdate CURSOR FOR 
	    SELECT LedgerAcc,IDX FROM acc_gltrans WHERE acc_gltrans.DocNo=@DisOrgDocNo AND acc_gltrans.CostCenter=@p_CostCenter and LedgerAcc=@p_LedgerCode1

		OPEN taxUpdate
		FETCH NEXT FROM taxUpdate INTO @p_LedgerAcc,@idx
		WHILE @@FETCH_STATUS = 0
		BEGIN
	
		UPDATE acc_gltrans SET acc_gltrans.Amount=acc_gltrans.Amount-@p_TaxAmt FROM acc_gltrans WHERE acc_gltrans.DocNo=@DisOrgDocNo AND acc_gltrans.CostCenter=@p_CostCenter and LedgerAcc=@p_LedgerAcc and IDX=@idx
        BREAK
	   ---------------------	

		FETCH NEXT FROM taxUpdate INTO @p_LedgerAcc,@idx
		END
		CLOSE taxUpdate
		DEALLOCATE taxUpdate	    
      -----------------
 	    INSERT INTO acc_gltrans(DocNo,Loca,Iid,LedgerAcc,DoubleEntery,Amount,CostCenter,DocumentDate,Created_User) VALUES(@DisOrgDocNo,@p_LocaCode,@p_Iid,@LedgerVat,'CR',@p_TaxAmt,@p_CostCenter,@p_DocumentDate,@p_User_Name) 

       FETCH NEXT FROM taxUpdateLeg INTO @Tax,@p_TaxAmt
		END
		CLOSE taxUpdateLeg
		DEALLOCATE taxUpdateLeg	    
  ---------------------

    END
 ---------------   
    
 
  --if @p_TaxAmount>0 and @p_OtherCharge>0    
      IF @p_TaxAmount=0 and @p_OtherCharge>0
    BEGIN  
    
  
     SELECT @LedgerOther=LedgerCode FROM acc_transactiontype WHERE Transtype='OTHR'     
    INSERT INTO acc_gltrans(DocNo,Serialno,Loca,Iid,LedgerAcc,DoubleEntery,Amount,CostCenter,DocumentDate,Created_User) SELECT @DisOrgDocNo,serialno,@p_LocaCode,@p_Iid,LedgerCode2,DoubleEntery2,Amount,@p_CostCenter,@p_DocumentDate,@p_User_Name FROM inv_temppayment WHERE inv_temppayment.TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode and (inv_temppayment.IID='IRE' or inv_temppayment.IID='OVP')
    INSERT INTO acc_gltrans(DocNo,Serialno,Loca,Iid,LedgerAcc,DoubleEntery,Amount,CostCenter,DocumentDate,Created_User) SELECT  @DisOrgDocNo,serialno,@p_LocaCode,@p_Iid,LedgerCode1,DoubleEntery1,Amount,@p_CostCenter,@p_DocumentDate,@p_User_Name FROM inv_temppayment WHERE inv_temppayment.TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode and (inv_temppayment.IID='IRE' or inv_temppayment.IID='OVP')
   
   
		DECLARE taxUpdate CURSOR FOR 
	    SELECT LedgerAcc,IDX FROM acc_gltrans WHERE acc_gltrans.DocNo=@p_OrgDocNo AND acc_gltrans.CostCenter=@p_CostCenter and LedgerAcc=@p_LedgerCode1

		OPEN taxUpdate
		FETCH NEXT FROM taxUpdate INTO @p_LedgerAcc,@idx
		WHILE @@FETCH_STATUS = 0
		BEGIN
	
		UPDATE acc_gltrans SET acc_gltrans.Amount=acc_gltrans.Amount-@p_OtherCharge FROM acc_gltrans WHERE acc_gltrans.DocNo=@DisOrgDocNo AND acc_gltrans.CostCenter=@p_CostCenter and LedgerAcc=@p_LedgerAcc and IDX=@idx
        BREAK
		
		FETCH NEXT FROM taxUpdate INTO @p_LedgerAcc,@idx
		END
		CLOSE taxUpdate
		DEALLOCATE taxUpdate	   
   
  
    INSERT INTO acc_gltrans(DocNo,Loca,Iid,LedgerAcc,DoubleEntery,Amount,CostCenter,DocumentDate,Created_User) VALUES(@DisOrgDocNo,@p_LocaCode,@p_Iid,@LedgerOther,'CR',@p_OtherCharge,@p_CostCenter,@p_DocumentDate,@p_User_Name) 

    END
 ---------------   
    
    
   


--///ssssssssss
CREATE TABLE #temp_commission
	(
	 TerminalId varchar(15) null,
     Amount decimal(10,2),
     Commission decimal(10,2),
     DrLedgerCode varchar(15) null,
     CrLegerCode varchar(15) null
	)
     INSERT INTO #temp_commission(TerminalId,Amount) SELECT DISTINCT TerminalId,sum(Amount) FROM inv_temppayment WHERE inv_temppayment.TempDocNo = @p_TempDocNo AND inv_temppayment.LocaCode = @p_LocaCode and TerminalId<>'' GROUP BY TerminalId  
	 UPDATE #temp_commission SET #temp_commission.Commission=gen_terminal.Commission,#temp_commission.CrLegerCode=gen_terminal.CrLegerCode,#temp_commission.DrLedgerCode=gen_terminal.DrLedgerCode FROM #temp_commission INNER JOIN gen_terminal ON #temp_commission.TerminalId COLLATE DATABASE_DEFAULT=gen_terminal.TerminalId COLLATE DATABASE_DEFAULT

    INSERT INTO acc_gltrans(DocNo,Serialno,Loca,Iid,LedgerAcc,DoubleEntery,Amount,CostCenter,DocumentDate,Created_User) SELECT @DisOrgDocNo,'',@p_LocaCode,@p_Iid,CrLegerCode,'DR',(Amount*#temp_commission.commission)*0.01,@p_CostCenter,@p_DocumentDate,@p_User_Name FROM #temp_commission
     INSERT INTO acc_gltrans(DocNo,Serialno,Loca,Iid,LedgerAcc,DoubleEntery,Amount,CostCenter,DocumentDate,Created_User) SELECT  @DisOrgDocNo,'',@p_LocaCode,@p_Iid,DrLedgerCode,'CR',(Amount*#temp_commission.Commission)*0.01,@p_CostCenter,@p_DocumentDate,@p_User_Name FROM #temp_commission


INSERT INTO gen_chequeregister (ChequeNo,Bank,Branch,AccCode,DocumentNo,LocaCode,Amount,TrDate,Iid,Tid,ChequeDate,CostCenter,type,trtype,Created_User)
		SELECT CardChequeNo,BankCode, BranchCode,@p_CustomerCode,@p_OrgDocNo,@p_LocaCode,sum(Amount),@p_DocumentDate, 'REC',0,ChequeDate,@p_CostCenter,'D','R',@p_User_Name FROM inv_temppayment WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND PaymentCode='007' AND (Iid='IRE' or Iid='OVP') group by CardChequeNo,BankCode, BranchCode,ChequeDate

	INSERT INTO inv_productsalesdetails(ProductCode, ProductDescription, CostPrice, UnitPrice, Qty, Amount, Iid,PackSize, DocumentNo, LocaCode, SaleDate,CostCenter,Created_Date, Discount, SDiscount, StatusId)
					SELECT ProductCode, ProductDescription, CostPrice, UnitPrice, (Qty + FreeQty), Amount, @p_Iid,PackSize, @p_OrgDocNo, @p_LocaCode, @p_DocumentDate,@p_CostCenter, getDate(), DiscAmount, ISNULL((Amount/@p_GrossAmount)*@p_DiscAmount,0),1  FROM inv_temptransaction WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND Iid = @p_Iid

	
	INSERT INTO inv_documentdetails(DocumentNo, Description, Amount, LocaCode, RefDocNo, Created_User)
			VALUES (@p_OrgDocNo, 'INVOICE POSTED', @p_NetAmount, @p_LocaCode, @p_TempDocNo, @p_User_Name)
   UPDATE gen_documentno SET orgdocumentno = orgdocumentno + 1 WHERE TransactionId = 'INM' AND LocaCode = @p_LocaCode AND Costcenter = @p_Costcenter
    INSERT INTO inv_invoicelinkcustomer(DocumentNo,MainCustomer,SubCustomer,LocaCode,Iid)SELECT @p_OrgDocNo,@p_CustomerCode,CustomerCode,@p_LocaCode,'INV'  FROM inv_templinkcustomer WHERE TempdocNo=@p_TempDocNo

    --///ssssssssss


	--Change by Jayan on 22/07/2012	
--	IF  @creditAmount>0
--    BEGIN
  --IF @p_GrnAmount>=@p_NetAmount AND @p_Grn<>''

    --BEGIN
    --INSERT INTO acc_gltrans(DocNo,Loca,Iid,LedgerAcc,DoubleEntery,Amount,Created_User) VALUES(@p_OrgDocNo,@p_LocaCode,@p_Iid,@p_LedgerCode2,@p_DoubleEntery2,@p_NetAmount,@p_User_Name)
    --INSERT INTO acc_gltrans(DocNo,Loca,Iid,LedgerAcc,DoubleEntery,Amount,Created_User) VALUES(@p_OrgDocNo,@p_LocaCode,@p_Iid,@p_LedgerCode1,@p_DoubleEntery1,@p_NetAmount,@p_User_Name)
	--INSERT INTO inv_paymentdocdetails (DocumentNo, AccCode, Iid,LocaCode,PaidDocumentNo, PaymentDate,CreditPeriod,Amount,BalanceAmount,Type,Tid,Created_User)
 --             VALUES(@p_OrgDocNo, @p_SupplierCode,@p_Iid, @p_LocaCode, @p_Grn, @p_DocumentDate,0,@p_NetAmount,@p_NetAmount,0,1,@p_User_Name) 
  
    

--END

 --  IF @p_GrnAmount<=@p_NetAmount OR @p_Grn=''
 --   BEGIN 
 --   INSERT INTO acc_gltrans(DocNo,Loca,Iid,LedgerAcc,DoubleEntery,Amount,Created_User) VALUES(@p_OrgDocNo,@p_LocaCode,@p_Iid,@p_LedgerCode1,@p_DoubleEntery1,ABS(@p_GrnAmount-@p_NetAmount),@p_User_Name)
 --   INSERT INTO acc_gltrans(DocNo,Loca,Iid,LedgerAcc,DoubleEntery,Amount,Created_User) VALUES(@p_OrgDocNo,@p_LocaCode,@p_Iid,@p_LedgerCode3,@p_DoubleEntery3,ABS(@p_GrnAmount-@p_NetAmount),@p_User_Name)
 -- 	UPDATE inv_paymentdocdetails SET TYPE = 7 from inv_paymentdocdetails WHERE inv_paymentdocdetails.LocaCode = @p_LocaCode and PaidDocumentNo=@p_Grn and Iid='RMRN'

	--INSERT INTO inv_paymentdocdetails (DocumentNo, AccCode, Iid,LocaCode,PaidDocumentNo, PaymentDate,CreditPeriod,Amount,BalanceAmount,Type,Tid,Created_User)
 --             VALUES(@p_OrgDocNo, @p_SupplierCode,@p_Iid, @p_LocaCode, @p_Grn, @p_DocumentDate,0,ABS(@p_GrnAmount-@p_NetAmount),ABS(@p_GrnAmount-@p_NetAmount),1,1,@p_User_Name) 
  

 -- END

   -------------------------------

  IF @p_ToDispach='False' and @p_DisRecall='False'
     BEGIN
	INSERT INTO inv_tempstockupdate(ProductCode, LocaCode, StockLocaCode, DocumentNo, Iid, Qty)
            SELECT it.ProductCode, it.LocaCode, it.StockLoca, @p_OrgDocNo, it.Iid, sum(it.Qty*it.packsize) +sum(it.FreeQty*it.packsize)as TotalQty  FROM inv_temptransaction it inner join inv_productmaster ip on it.ProductCode=ip.ProductCode WHERE Iid = @p_Iid AND TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode and Ip.Service=0 group by it.StockLoca,it.LocaCode,it.ProductCode,it.iid
	UPDATE SM SET SM.StockQty = SM.StockQty - TM.Qty From inv_productstockmaster SM INNER JOIN inv_tempstockupdate TM ON TM.ProductCode COLLATE DATABASE_DEFAULT = SM.ProductCode COLLATE DATABASE_DEFAULT AND TM.StockLocaCode COLLATE DATABASE_DEFAULT = SM.LocaCode COLLATE DATABASE_DEFAULT WHERE TM.Iid = @p_Iid AND TM.DocumentNo = @p_OrgDocNo AND TM.LocaCode = @p_LocaCode
	END	
	
  IF @p_DisRecall='True'
     BEGIN
     UPDATE inv_invoiceheader SET Recall=1,Reference=@p_OrgDocNo FROM inv_invoiceheader INNER JOIN inv_tempdispatchno on inv_invoiceheader.Documentno=inv_tempdispatchno.DispatchNo WHERE inv_tempdispatchno.TempDocumentNo=@p_TempDocNo
     INSERT INTO inv_invoicedetailsdispatch(DocumentNo,LocaCode,Iid,DocumentDate,CustomerCode,CostCenter,Dispatch) SELECT @p_OrgDocNo,@p_LocaCode,'DIP',@p_DocumentDate,@p_CustomerCode,@p_CostCenter,DispatchNo FROM inv_tempdispatchno WHERE inv_tempdispatchno.TempDocumentNo=@p_TempDocNo
     DELETE FROM inv_tempdispatchno WHERE inv_tempdispatchno.TempDocumentNo=@p_TempDocNo
  END	
	
	
	--Bundle Up Update

IF EXISTS(SELECT inv_tempstockupdate.ProductCode FROM inv_tempstockupdate INNER JOIN inv_productmaster on inv_tempstockupdate.ProductCode COLLATE DATABASE_DEFAULT=inv_productmaster.ProductCode COLLATE DATABASE_DEFAULT   WHERE inv_tempstockupdate.Iid = @p_Iid AND inv_tempstockupdate.DocumentNo = @p_OrgDocNo AND inv_tempstockupdate.LocaCode = @p_LocaCode and inv_productmaster.Bundled='true')
BEGIN
 CREATE TABLE #temp_bundle
	(
	 ProductCode varchar(15) null,
     SubCode varchar(15) null,
     Qty decimal(10,2),
     Loca varchar(15) null
  
	)

INSERT INTO #temp_bundle(ProductCode,SubCode,Qty,Loca) SELECT inv_tempstockupdate.ProductCode,inv_bundleupmaster.BundleCode,(inv_tempstockupdate.QTY*inv_bundleupmaster.Quantity),inv_tempstockupdate.StockLocaCode FROM inv_tempstockupdate INNER JOIN inv_productmaster on inv_tempstockupdate.ProductCode COLLATE DATABASE_DEFAULT=inv_productmaster.ProductCode COLLATE DATABASE_DEFAULT INNER JOIN inv_bundleupmaster ON inv_tempstockupdate.ProductCode COLLATE DATABASE_DEFAULT=inv_bundleupmaster.ProductCode COLLATE DATABASE_DEFAULT WHERE inv_tempstockupdate.Iid = @p_Iid AND inv_tempstockupdate.DocumentNo = @p_OrgDocNo AND inv_tempstockupdate.LocaCode = @p_LocaCode and inv_productmaster.Bundled='true'
UPDATE SM SET SM.StockQty = SM.StockQty - TB.Qty From inv_productstockmaster SM INNER JOIN #temp_bundle TB ON TB.SubCode COLLATE DATABASE_DEFAULT = SM.ProductCode COLLATE DATABASE_DEFAULT AND TB.Loca COLLATE DATABASE_DEFAULT = SM.LocaCode COLLATE DATABASE_DEFAULT-- WHERE TM.Iid = @p_Iid AND TM.DocumentNo = @p_OrgDocNo AND TM.LocaCode = @p_LocaCode


END
	
			
INSERT INTO inv_coloursizereceived(ProductCode,Barcode,DocumentNo,Qty,Iid,price,DocumentDate) SELECT ProductCode,barcode,@p_OrgDocNo,qTY,iid,Price,@p_DocumentDate FROM inv_tempcolursize WHERE Iid = @p_Iid AND TempDocNo = @p_TempDocNo
DELETE FROM TEMP
INSERT INTO TEMP(ProductCode,Qty) select barcode,sum(Qty) FROM inv_tempcolursize WHERE Iid = @p_Iid AND TempDocNo = @p_TempDocNo group by barcode
UPDATE ic SET ic.Qty = ic.Qty- TM.Qty From inv_coloursize ic INNER JOIN TEMP TM ON ic.Barcode = TM.ProductCode 
	
	
	
	UPDATE gen_documentno SET orgdocumentno = orgdocumentno + 1 WHERE TransactionId = @p_Iid AND LocaCode = @p_LocaCode AND Costcenter = @p_Costcenter
	-------------------------------Batch Detials Update
	DELETE FROM inv_tempbatchstockcheck
	INSERT INTO inv_tempbatchstockcheck(ProductCode,Batchno,Locacode,DocumentNo, Iid, TrQty,SQty,CostCenter)
				SELECT inv_temptransaction.ProductCode,inv_temptransaction.Batchno,inv_temptransaction.StockLoca,@p_TempDocNo, inv_temptransaction.Iid, sum(inv_temptransaction.Qty*inv_temptransaction.packsize) +sum(inv_temptransaction.FreeQty*inv_temptransaction.packsize)as TotalQty,0,CostCenter  FROM inv_temptransaction  WHERE inv_temptransaction.Iid = @p_Iid AND inv_temptransaction.TempDocNo = @p_TempDocNo AND inv_temptransaction.LocaCode = @p_LocaCode AND inv_temptransaction.CostCenter = @p_CostCenter  group by inv_temptransaction.StockLoca,inv_temptransaction.CostCenter,inv_temptransaction.ProductCode,inv_temptransaction.iid,inv_temptransaction.Batchno
	update inv_batchdetails set inv_batchdetails.qty=inv_batchdetails.Qty- inv_tempbatchstockcheck.TrQty from inv_tempbatchstockcheck inner join inv_batchdetails on inv_tempbatchstockcheck.ProductCode COLLATE DATABASE_DEFAULT=inv_batchdetails.ProductCode COLLATE DATABASE_DEFAULT and inv_tempbatchstockcheck.LocaCode COLLATE DATABASE_DEFAULT=inv_batchdetails.LocaCode COLLATE DATABASE_DEFAULT and inv_tempbatchstockcheck.Batchno COLLATE DATABASE_DEFAULT=inv_batchdetails.DocumentNo COLLATE DATABASE_DEFAULT and inv_tempbatchstockcheck.CostCenter COLLATE DATABASE_DEFAULT=inv_batchdetails.CostCenter COLLATE DATABASE_DEFAULT 


	-------------------------------Expiry Detials Update


	update inv_expirydetails set inv_expirydetails.qty=inv_expirydetails.qty -inv_temptransaction.Qty* inv_temptransaction.packsize
	from inv_expirydetails inner join inv_temptransaction on inv_expirydetails.DocumentDate =inv_temptransaction.ExpiryDate  and inv_expirydetails.Locacode COLLATE DATABASE_DEFAULT=inv_temptransaction.StockLoca COLLATE DATABASE_DEFAULT AND inv_expirydetails.Productcode COLLATE DATABASE_DEFAULT=inv_temptransaction.Productcode COLLATE DATABASE_DEFAULT and inv_expirydetails.Costcenter COLLATE DATABASE_DEFAULT=inv_temptransaction.Costcenter COLLATE DATABASE_DEFAULT     
	WHERE inv_temptransaction.Iid = @p_Iid AND TempDocNo = @p_TempDocNo AND inv_temptransaction.LocaCode = @p_LocaCode AND inv_temptransaction.CostCenter = @p_Costcenter  AND (inv_expirydetails.IID='GRN' or inv_expirydetails.IID='TOG' or inv_expirydetails.IID='SA')


	-------------------------------Tax Detials Update
  INSERT INTO inv_grntaxdetails(DocumentNo,Tax,Amount,Loca,iid,GroupId,CostCenter) SELECT @p_OrgDocNo,Tax,Amount,Loca,iid,GroupId,@p_CostCenter FROM gen_temptaxdetails WHERE TempDocno=@p_TempDocNo and Loca=@p_Locacode and Iid=@p_Iid


	-------------------------------Discount Detials Update
   INSERT INTO inv_transdiscount(DocumentNo,LocaCode,CostCenter,Code,Name,Perc,Amount,Iid) SELECT @p_OrgDocNo,@p_LocaCode,@p_CostCenter,Code,Name,Perc,Amount,Iid FROM inv_tempdiscount WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND CostCenter = @p_CostCenter AND Iid = @p_Iid 

	-------------------------------FIFO Update
  INSERT INTO inv_fifodetails(DocumentNo,Iid,LocaCode,DocumentDate,ProductCode,Qty,CostPrice,UnitPrice,CostCenter,unit,packsize,Created_User)
	SELECT @p_OrgDocNo, @p_Iid, StockLoca, @p_DocumentDate, ProductCode,packsize*(Qty+FreeQty),CostPrice, UnitPrice,@p_CostCenter,unit,packsize,@p_User_Name  FROM inv_temptransaction WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND Iid = @p_Iid


   INSERT INTO inv_warrantydetails(DocumentNo,LocaCode,ProductCode,SerialNo,warranty,iid,Tid) SELECT @p_OrgDocNo,LocaCode,ProductCode, SerialNo,WarrantyPeriod,Iid,@p_Iid FROM inv_tmpWarrantydetails WHERE DocumentNo=@p_TempDocNo and Iid=1
    
    IF @p_ToDispach='False' and @p_DisRecall='False'
     BEGIN
    UPDATE inv_serialmaster set iid=0 from inv_tmpWarrantydetails inner join inv_serialmaster on inv_tmpWarrantydetails.SerialNo COLLATE DATABASE_DEFAULT=inv_serialmaster.SerialNo COLLATE DATABASE_DEFAULT and inv_tmpWarrantydetails.Locacode COLLATE DATABASE_DEFAULT=inv_serialmaster.Locacode COLLATE DATABASE_DEFAULT WHERE DocumentNo=@p_TempDocNo and inv_tmpWarrantydetails.Iid=1 
     END


	DELETE FROM inv_temptransaction WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND Iid = @p_Iid
	DELETE FROM inv_temppaymentdetails WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode 
	DELETE FROM inv_tempsalesorderdetails WHERE DocumentNo = @p_TempDocNo  

    DELETE FROM inv_tempstockupdate WHERE Iid = @p_Iid AND DocumentNo = @p_OrgDocNo AND LocaCode = @p_LocaCode
    DELETE FROM inv_tmpWarrantydetails WHERE DocumentNo=@p_tempdocno and Iid=1 and LocaCode=@p_LocaCode
    DELETE FROM gen_temptaxdetails WHERE TempDocno=@p_TempDocNo and Loca=@p_Locacode and Iid=@p_Iid
    DELETE FROM inv_temppayment WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND (Iid = 'IRE' OR Iid = 'OVP')
  	DELETE FROM inv_tempdiscount WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND CostCenter = @p_CostCenter AND Iid = @p_Iid 
    DELETE FROM inv_templinkcustomer WHERE TempDocNo = @p_TempDocNo
	DELETE FROM inv_tempcolursize WHERE Iid = @p_Iid AND TempDocNo = @p_TempDocNo

	IF @p_QuoRecall=1
	BEGIN
	UPDATE inv_invoiceheader SET Recall='True' WHERE DocumentNo=@p_Quotation AND LocaCode=@p_LocaCode AND IID='QUO' AND CostCenter=@p_CostCenter AND StatusId=1 AND Recall='False'
	UPDATE inv_invoicedetails SET Recall='True' WHERE DocumentNo=@p_Quotation AND LocaCode=@p_LocaCode AND IID='QUO' AND CostCenter=@p_CostCenter AND StatusId=1 AND Recall='False'
	END
	
	IF @p_SonRecall=1
	BEGIN
	--UPDATE inv_invoiceheader SET Recall='True' WHERE DocumentNo=@p_Performer AND LocaCode=@p_LocaCode AND IID='SON' AND CostCenter=@p_CostCenter AND StatusId=1 AND Recall='False'
	--UPDATE inv_invoicedetails SET Recall='True' WHERE DocumentNo=@p_Performer AND LocaCode=@p_LocaCode AND IID='SON' AND CostCenter=@p_CostCenter AND StatusId=1 AND Recall='False'
	 UPDATE inv_invoicedetails SET BQty=BQty-inv_tempstockupdate.Qty FROM inv_invoicedetails INNER JOIN inv_tempstockupdate ON inv_invoicedetails.ProductCode=inv_tempstockupdate.ProductCode AND inv_invoicedetails.LocaCode=inv_tempstockupdate.LocaCode WHERE inv_invoicedetails.Iid='SON' AND inv_invoicedetails.DocumentNo=@p_Performer AND inv_invoicedetails.LocaCode=@p_LocaCode AND inv_invoicedetails.StatusId=1 AND inv_invoicedetails.CostCenter=@p_CostCenter
    IF EXISTS(SELECT ISNULL(SUM(BQTY),0) FROM inv_invoicedetails WHERE inv_invoicedetails.Iid='SON' AND inv_invoicedetails.DocumentNo=@p_Performer AND inv_invoicedetails.LocaCode=@p_LocaCode AND inv_invoicedetails.StatusId=1 AND inv_invoicedetails.CostCenter=@p_CostCenter HAVING ISNULL(SUM(BQTY),0)=0)
    UPDATE inv_invoiceheader SET Recall='True'  WHERE inv_invoiceheader.Iid='SON' AND inv_invoiceheader.DocumentNo=@p_Performer AND inv_invoiceheader.LocaCode=@p_LocaCode AND inv_invoiceheader.StatusId=1 AND inv_invoiceheader.CostCenter=@p_CostCenter

	
	END
	IF @p_DisRecall=1
	BEGIN
	UPDATE inv_invoiceheader SET Recall='True' WHERE DocumentNo=@p_Dispatch AND LocaCode=@p_LocaCode AND IID='DIP' AND CostCenter=@p_CostCenter AND StatusId=1 AND Recall='False'
	UPDATE inv_invoicedetails SET Recall='True' WHERE DocumentNo=@p_Dispatch AND LocaCode=@p_LocaCode AND IID='DIP' AND CostCenter=@p_CostCenter AND StatusId=1 AND Recall='False'
	END






	IF @p_Recall=1
	BEGIN
 
    DELETE FROM inv_invoiceheader WHERE DocumentNo=@p_SaveDocNo AND LocaCode=@p_LocaCode AND IID=@p_Iid AND CostCenter=@p_CostCenter AND StatusId=0
    DELETE FROM inv_invoicedetails WHERE DocumentNo=@p_SaveDocNo AND LocaCode=@p_LocaCode AND IID=@p_Iid AND CostCenter=@p_CostCenter  AND StatusId=0
  	DELETE FROM inv_savetransdiscount WHERE DocumentNo = @p_SaveDocNo AND LocaCode = @p_LocaCode AND CostCenter = @p_CostCenter AND Iid = @p_Iid 

	END
	 



END


IF (@p_DocAction = 'S')
BEGIN	

	INSERT INTO inv_invoiceheader (DocumentNo, LocaCode, Iid, DocumentDate, CustomerCode,SalesmanCode, ManualNo, Reference, Remarks, CreditPeriod, GrossAmount, DiscPer, DiscAmount, TaxPer, TaxAmount, NetAmount, BalanceAmount, StatusId,CostCenter,JobNumber,OtherCharge,SalesType,PriceLevel,Quotation,Performer,Dispatch,TempCreditAmt,RoudAmt,TourCode,PoDate,Created_User)
			VALUES (@p_OrgDocNo, @p_LocaCode, @p_Iid, @p_DocumentDate, @p_CustomerCode,@p_SalesmanCode, @p_ManualNo, @p_Reference, @p_Remarks, @p_CreditPeriod, @p_GrossAmount, @p_DiscPer, @p_DiscAmount, @p_TaxPer, @p_TaxAmount, @p_NetAmount, @p_NetAmount, 0,@p_CostCenter,@p_JobNumber,@p_OtherCharge,@p_SalesType,@p_PriceLevel,@p_Quotation,@p_Performer,@p_Dispatch,@p_TempCreditAmt,@p_RoudAmt,@p_TourCode,@p_PODate,@p_User_Name)

	INSERT INTO inv_invoicedetails (DocumentNo, Iid, LocaCode, DocumentDate, ProductCode, ProductDescription,LongDescription, Margin, Unit, PackSize, Qty, FreeQty, CostPrice, UnitPrice, WholeSalePrice,BatchNo,ExpiryDate, DiscPer, DiscAmount, Amount, StockLoca, Tax, StatusId,RefCode,CostCenter,Created_User)
			SELECT @p_OrgDocNo, @p_Iid, @p_LocaCode, @p_DocumentDate, ProductCode, ProductDescription,LongDescription, Margin, Unit, PackSize, Qty, FreeQty, CostPrice, UnitPrice, WholeSalePrice,BatchNo,ExpiryDate,DiscPer, DiscAmount, Amount, StockLoca, Tax, 0,RefCode,@p_CostCenter,@p_User_Name  FROM inv_temptransaction WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND Iid = @p_Iid
   

	UPDATE gen_documentno SET savedocumentno = savedocumentno + 1 WHERE TransactionId = @p_Iid AND LocaCode = @p_LocaCode AND Costcenter = @p_Costcenter
	
	INSERT INTO inv_documentdetails(DocumentNo, Description, Amount, LocaCode, RefDocNo, Created_User)
			VALUES (@p_OrgDocNo, 'INVOICE SAVE', @p_NetAmount, @p_LocaCode, @p_TempDocNo, @p_User_Name)


   INSERT INTO inv_savewarrantydetails(DocumentNo,LocaCode,ProductCode,SerialNo,WarrantyPeriod,iid,Tid) SELECT @p_OrgDocNo,LocaCode,ProductCode, SerialNo,WarrantyPeriod,Iid,@p_Iid FROM inv_tmpWarrantydetails WHERE DocumentNo=@p_TempDocNo and Iid=1 and LocaCode=@p_LocaCode
   INSERT INTO inv_grnsavetaxdetails(DocumentNo,Tax,Amount,Loca,iid,GroupId) SELECT @p_OrgDocNo,Tax,Amount,Loca,iid,GroupId FROM gen_temptaxdetails WHERE TempDocno=@p_TempDocNo and Loca=@p_Locacode and Iid=@p_Iid
   INSERT INTO inv_savetransdiscount(DocumentNo,LocaCode,CostCenter,Code,Name,Perc,Amount,Iid) SELECT @p_OrgDocNo,@p_LocaCode,@p_CostCenter,Code,Name,Perc,Amount,Iid FROM inv_tempdiscount WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND CostCenter = @p_CostCenter AND Iid = @p_Iid 

	DELETE FROM inv_temptransaction WHERE TempDocNo = @p_TempDocNo AND LocaCode = @p_LocaCode AND Iid = @p_Iid
   -- DELETE FROM inv_tempstockupdate WHERE Iid = @p_Iid AND DocumentNo = @p_OrgDocNo AND LocaCode = @p_LocaCode
    DELETE FROM inv_tmpWarrantydetails WHERE DocumentNo=@p_tempdocno and Iid=1 and LocaCode=@p_LocaCode
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






