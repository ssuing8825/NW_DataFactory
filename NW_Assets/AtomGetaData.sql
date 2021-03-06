USE [NSLIJHS_Atom]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROC [dbo].[usp_AtomGetData]
	(@sessionid uniqueidentifier, 
	@count int)
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.	
	SET NOCOUNT ON;

	exec [dbo].[usp_AtomCallStackPush] @@PROCID

	DECLARE @RowsAffected int = 0
	DECLARE @ErrorMessage NVARCHAR(4000) = ''
	DECLARE @ErrorSeverity INT = 0
	DECLARE @ErrorState INT = 0
	declare @resultsxml xml = null
	declare @getdatasproc nvarchar(MAX) = ''
	declare @atomresponse nvarchar(max) = ''
	declare @sessiontype nvarchar(max) = ''

	set @atomresponse = ''
	BEGIN TRY
		
		-- check the validity of @sessionid
		if not exists(select 1 from TAtomSession where GUID = @sessionid)
			RAISERROR('Invalid session id.', 11, 109)

		select 
			@sessiontype = isnull(tast.type, '') 
		from
			TAtomSessionType tast
			inner join TAtomSession tas on tas.type = tast.GUID and tas.GUID = @sessionid 

		-- get the xml root value and getdata stored proc
		declare @XmlRoot nvarchar(max) = 'XmlRoot'
		select @XmlRoot = isnull(xmlroot, ''), @getdatasproc = isnull(getdata, '') from TAtomSessionType ast inner join TAtomSession tas on tas.type = ast.GUID and tas.GUID = @sessionid
		if @XmlRoot = ''
			set @XmlRoot = 'XmlRoot'

		if @getdatasproc = ''
			set @getdatasproc = 'usp_AtomGetDataDefault'
		set @getdatasproc =  @getdatasproc + ' @sessionid, @count, @resultsxml OUTPUT, @rowsaffected OUTPUT'

		EXEC sp_executesql @getdatasproc, N'@sessionid uniqueidentifier, @count int, @resultsxml xml OUTPUT, @rowsaffected int OUTPUT', @sessionid = @sessionid, @count = @count, @resultsxml = @resultsxml OUTPUT, @rowsaffected = @RowsAffected OUTPUT
--		exec [dbo].[usp_AtomGetDataDefault] @sessionid, @count, @resultsxml OUTPUT, @rowsaffected OUTPUT
	END TRY
	BEGIN CATCH
	    SELECT 
			@ErrorMessage = OBJECT_NAME(@@PROCID) + '(' + CAST(ERROR_LINE() AS VARCHAR(50)) + '): ' + ERROR_MESSAGE(),
	        @ErrorSeverity = ERROR_SEVERITY(),
		    @ErrorState = ERROR_STATE();
	END CATCH

	if @ErrorMessage <> ''
	begin
		set @atomresponse = 
			'<AtomResponse>
				<Error>
					<ErrorMessage>' + @ErrorMessage + '</ErrorMessage>
				</Error>
				<Status>Fail</Status>
			</AtomResponse>'
		exec [dbo].[usp_AtomLogger] @sessionid = @sessionid, @application = @sessiontype, @data = @atomresponse, @message = N''
	end
	else
	BEGIN
		set @atomresponse = 
		(
			select * from 
			(
				SELECT
					1 AS Tag,
					NULL AS Parent,
					NULL AS 'AtomResponse!1',
					NULL AS 'SessionInfo!2!SessionId!Element',
					NULL AS 'RemainingCount!3!',
					NULL AS 'ResponseData!4!Payload!CDATA'
				union all
				select
					2 AS Tag,
					1 AS Parent,
					NULL,
					@sessionid,
					NULL,
					NULL
				union all
				select
					3 AS Tag,
					1 AS Parent,
					NULL,
					NULL,
					@RowsAffected,
					NULL
				union all
				select
					4 AS Tag,
					1 AS Parent,
					NULL,
					NULL,
					NULL,
					convert(nvarchar(MAX), @resultsxml)
			) as K
			FOR XML EXPLICIT
		)
		exec [dbo].[usp_AtomLogger] @sessionid = @sessionid, @application = @sessiontype, @data = @atomresponse, @message = N''
	END
	exec [dbo].[usp_AtomCallStackPop]
	select @atomresponse as atomresponse
END