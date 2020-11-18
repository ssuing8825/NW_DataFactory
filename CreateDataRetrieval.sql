Create PROCEDURE [dbo].[RetrieveData]
AS

SELECT top (10) abb.CustomerId
      ,(Select * FROM [SalesLT].[Customer] c
             Left OUTER JOIN SalesLT.CustomerAddress ca
                on c.CustomerID = ca.CustomerID 
            left outer JOIN SalesLT.Address a on ca.AddressID = a.AddressID 
            WHERE abb.CustomerID = c.CustomerID 
            FOR XML PATH('Customer') ) AS RowXML
FROM [SalesLT].[Customer] AS abb