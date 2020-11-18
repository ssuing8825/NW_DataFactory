Create PROCEDURE [dbo].[ManipulateXml]
AS

UPDATE customerxml
SET customerxml.modify('insert <gender>Male</gender> into (/Customer)[1]')

