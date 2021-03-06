USE [NSLIJHS_Atom]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[usp_SCM_Observations_InitData]
	@atomrequest xml,
	@results xml OUTPUT
AS
	BEGIN TRY
		-- SET NOCOUNT ON added to prevent extra result sets from
		-- interfering with SELECT statements.	
		SET NOCOUNT ON;

		declare @startDate datetime
		declare @endDate datetime
		declare @facility nvarchar(max) = ''
		declare @nullguid uniqueidentifier = '00000000-0000-0000-0000-000000000000'
		declare @sessionid uniqueidentifier = '00000000-0000-0000-0000-000000000000'
		declare @referenceid int = null
		declare @isbackload bit = 0

			begin try
				set @startDate = @atomrequest.value('(/AtomRequest/DateTime/StartDate)[1]', 'datetime')
			end try
			BEGIN CATCH
				set @startDate = null
			end catch
			if @startDate is null
				RAISERROR('Invalid /AtomRequest/DateTime/StartDate.', 11, 104)

			begin try
				set @endDate = @atomrequest.value('(/AtomRequest/DateTime/EndDate)[1]', 'datetime')
			end try
			BEGIN CATCH
				set @endDate = null
			end catch
			if @endDate is null
				RAISERROR('Invalid /AtomRequest/DateTime/EndDate.', 11, 105)

			if @startDate > @endDate
				RAISERROR('Inconsistent dates: StartDate > EndDate.', 11, 106)
--		end

		begin try
			set @sessionid = isnull(@atomrequest.value('(/AtomRequest/SessionInfo/SessionId)[1]', 'uniqueidentifier'), @nullguid)
		end try
		BEGIN CATCH
			set @sessionid = @nullguid
		end catch
		if @sessionid = @nullguid
			RAISERROR('Invalid /AtomRequest/SessionInfo/SessionId.', 11, 107)

--		if @referenceid is not null
			insert into [dbo].[TInitData](GUID, pk1, Rownum, Results)
			EXEC	[dbo].[usp_SCM_Observations_InitData_Internal_Current]
						@starttime = @startDate,
						@endtime = @endDate,
						@sessionid = @sessionid
	END TRY

	BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000)
        DECLARE @ErrorSeverity INT
        DECLARE @ErrorState INT
 
        SELECT	@ErrorMessage = OBJECT_NAME(@@PROCID) + '(' + CAST(ERROR_LINE() AS VARCHAR(50)) + '): ' + ERROR_MESSAGE(),
								@ErrorSeverity = ERROR_SEVERITY(),
								@ErrorState = ERROR_STATE()
 
        RAISERROR ( @ErrorMessage, @ErrorSeverity, @ErrorState)
	END CATCH

	RETURN 1