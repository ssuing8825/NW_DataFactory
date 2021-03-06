USE [NSLIJHS_Atom]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROC [dbo].[usp_AtomOpenSession]
	(@atomrequest xml([dbo].[AtomRequestSchema]))
AS
	SET NOCOUNT ON;

	exec [dbo].[usp_AtomCallStackPush] @@PROCID

	declare @nullguid uniqueidentifier = '00000000-0000-0000-0000-000000000000'
	declare @sessionid uniqueidentifier = '00000000-0000-0000-0000-000000000000'
	declare @sessiontype nvarchar(32) = ''
	declare @initdatasproc nvarchar(MAX) = ''
	declare @xmlnode nvarchar(128) = ''
	DECLARE @ErrorMessage NVARCHAR(4000) = ''
	DECLARE @ErrorSeverity INT = 0
	DECLARE @ErrorState INT = 0
	declare @atomresponsexml xml([dbo].[AtomResponseSchema]) = null
	declare @message nvarchar(max) = ''

	BEGIN TRY
		select @sessiontype = rtrim(ltrim(isnull(@atomrequest.value('(/AtomRequest/SessionType)[1]', 'nvarchar(32)'), '')))
		if @sessiontype = ''
			RAISERROR('No Atom SessionType was provided.', 11, 100)

		if not exists(select 1 from TAtomSessionType where type = @sessiontype and active = 1)
			RAISERROR('Atom SessionType is not supported.', 11, 101)

		select @initdatasproc = isnull(initdata, ''), @xmlnode = isnull('/' + xmlroot + '/' + xmlnode, '') from TAtomSessionType where type = @sessiontype
		if @initdatasproc = '' Or @xmlnode = ''
			RAISERROR('No stored procedure or xml data configured for Atom SessionType.', 11, 102)

		set @sessionid = NEWID()
		insert into TAtomSession(GUID, createdt, type, initdata) select @sessionid, GETDATE(), ast.GUID, cast(@atomrequest as nvarchar(max)) from TAtomSessionType ast where ast.type = @sessiontype and ast.active = 1
		if @@rowcount = 0
			set @sessionid = @nullguid

		if @sessionid = @nullguid
			RAISERROR('Unknown error.', 11, 103)

		set @atomrequest.modify('
			insert <SessionInfo><SessionType>{sql:variable("@sessiontype")}</SessionType><SessionId>{sql:variable("@sessionid")}</SessionId></SessionInfo>
			into (/AtomRequest)[1]
		')

		set @message = cast(@atomrequest as nvarchar(max))
		exec [dbo].[usp_AtomLogger] @sessionid = @sessionid, @application = @sessiontype, @data = @message, @message = N''

		declare @resultsxml xml = null
		declare @sql nvarchar(MAX) = '[dbo].[' + @initdatasproc + '] @initdata, @results OUTPUT'
		EXEC sp_executesql @sql, N'@initdata xml, @results xml OUTPUT', @initdata = @atomrequest, @results = @resultsxml OUTPUT
		
		declare @RowsAffected int = 0;
		select @RowsAffected = isnull(count(*), 0) from [dbo].[TInitData] where GUID = @sessionid

	END TRY
	BEGIN CATCH
	    SELECT 
			@ErrorMessage = OBJECT_NAME(@@PROCID) + '(' + CAST(ERROR_LINE() AS VARCHAR(50)) + '): ' + ERROR_MESSAGE(),
	        @ErrorSeverity = ERROR_SEVERITY(),
		    @ErrorState = ERROR_STATE();
		set @sessionid = @nullguid
	END CATCH

	declare @status nvarchar(16) = 'Success'
	if @sessionid <> @nullguid
	begin
		set @atomresponsexml = 
		(
			'<AtomResponse>
				<SessionInfo>
					<SessionType>' + @sessiontype + '</SessionType>
					<SessionId>' + cast(@sessionid as nvarchar(MAX)) + '</SessionId>
				</SessionInfo>
				<RemainingCount>' + cast(@RowsAffected as nvarchar(MAX)) + '</RemainingCount>
				<Status>' + @status + '</Status>
			</AtomResponse>'
		)

	end
	else
	BEGIN
		set @status = 'Fail'
		if @ErrorState = 108
			set @status = 'NoData'
		if @sessionid <> @nullguid
			exec [dbo].[usp_AtomCloseSession] @sessionid = @sessionid
		set @atomresponsexml = 
		(
			'<AtomResponse>
				<Status>' + @status + '</Status>
				<Error>
					<ErrorID>' + cast(@ErrorState as nvarchar(16)) + '</ErrorID>
					<ErrorMessage>' + @ErrorMessage + '</ErrorMessage>
				</Error>
			</AtomResponse>'
		)
	END 
	declare @atomresponse nvarchar(max) = convert(nvarchar(max), @atomresponsexml)
	exec [dbo].[usp_AtomLogger] @sessionid = @sessionid, @application = @sessiontype, @data = @atomresponse, @message = N''
	exec [dbo].[usp_AtomCallStackPop]
	select @atomresponse as atomresponse