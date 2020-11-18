--CREATE TABLE #tempXml (
--    customerXml VARCHAR(MAX)
--);




SELECT top(10) * 
FROM [SalesLT].[Customer] c
INNER JOIN SalesLT.CustomerAddress ca
    on c.CustomerID = ca.CustomerID 
INNER JOIN SalesLT.Address a on ca.AddressID = ca.AddressID
FOR XML RAW ('Customer'), ROOT ('Customers'), ELEMENTS XSINIL; 

SELECT top (10) abb.CustomerId
      ,(Select * FROM [SalesLT].[Customer] c
             Left OUTER JOIN SalesLT.CustomerAddress ca
                on c.CustomerID = ca.CustomerID 
            left outer JOIN SalesLT.Address a on ca.AddressID = a.AddressID 
            WHERE abb.CustomerID = c.CustomerID 
            FOR XML PATH('Customer') ) AS RowXML
FROM [SalesLT].[Customer] AS abb


Select * FROM [SalesLT].[Customer] c where c.CustomerID = 12 
Select * FROM [SalesLT].[CustomerAddress] c where c.CustomerID = 12 