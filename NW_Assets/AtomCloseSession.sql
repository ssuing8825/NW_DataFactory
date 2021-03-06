USE [NSLIJHS_Atom]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROC [dbo].[usp_AtomCloseSession]
	(@sessionid uniqueidentifier)
AS

	SET NOCOUNT ON;

	exec [dbo].[usp_AtomCallStackPush] @@PROCID

	DECLARE @ErrorMessage NVARCHAR(4000) = ''
	DECLARE @ErrorSeverity INT = 0
	DECLARE @ErrorState INT = 0
	DECLARE @status bit = 0
	declare @atomresponsexml xml([dbo].[AtomResponseSchema]) = null
	DECLARE @sessiontype nvarchar(max) = ''

	if exists(select 1 from [dbo].TAtomSession where GUID = @sessionid)
	BEGIN
		select 
			@sessiontype = isnull(tast.type, '') 
		from
			TAtomSessionType tast
			inner join TAtomSession tas on tas.type = tast.GUID and tas.GUID = @sessionid 

		declare @message nvarchar(max) = ''
		set @message = '<AtomRequest><SessionType>' + @sessiontype + '</SessionType><SessionInfo><SessionId>' + cast(@sessionid as nvarchar(max)) + '</SessionId></SessionInfo></AtomRequest>'
		exec [dbo].[usp_AtomLogger] @sessionid = @sessionid, @application = @sessiontype, @data = @message, @message = N''

		BEGIN TRY
			SELECT 1
			WHILE @@ROWCOUNT > 0
			BEGIN
				DELETE TOP (10000) FROM [dbo].TGetData where GUID = @sessionid
			END
			SELECT 1
			WHILE @@ROWCOUNT > 0
			BEGIN
				DELETE TOP (10000) FROM [dbo].TInitData where GUID = @sessionid
			END
			delete [dbo].TAtomSession where GUID = @sessionid
			set @status = 1
		END TRY
		BEGIN CATCH
		    SELECT 
				@ErrorMessage = OBJECT_NAME(@@PROCID) + '(' + CAST(ERROR_LINE() AS VARCHAR(50)) + '): ' + ERROR_MESSAGE(),
			    @ErrorSeverity = ERROR_SEVERITY(),
				@ErrorState = ERROR_STATE();
		END CATCH
	END
	ELSE
	BEGIN
		set @ErrorMessage = 'Invalid session id.'
	END

	if @status = 1
	begin
		set @atomresponsexml = 
		(
			'<AtomResponse>
				<SessionInfo>
					<SessionType>' + @sessiontype + '</SessionType>
					<SessionId>' + cast(@sessionid as nvarchar(MAX)) + '</SessionId>
				</SessionInfo>
				<RemainingCount>0</RemainingCount>
				<Status>Success</Status>
			</AtomResponse>'
		)

	end
	else
	BEGIN
		set @atomresponsexml = 
		(
			'<AtomResponse>
				<Error>
					<ErrorID>' + cast(@ErrorState as nvarchar(16)) + '</ErrorID>
					<ErrorMessage>' + @ErrorMessage + '</ErrorMessage>
				</Error>
				<Status>Fail</Status>
			</AtomResponse>'
		)
	END
	DECLARE @atomresponse nvarchar(max) = cast(@atomresponsexml as nvarchar(max))
	exec [dbo].[usp_AtomLogger] @sessionid = @sessionid, @application = @sessiontype, @data = @atomresponse, @message = N''
	exec [dbo].[usp_AtomCallStackPop]
	select @atomresponse as atomresponse