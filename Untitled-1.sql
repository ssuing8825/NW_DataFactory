SELECT top(10) * 
FROM [SalesLT].[Customer] c
INNER JOIN SalesLT.CustomerAddress ca
    on c.CustomerID = ca.CustomerID 
INNER JOIN SalesLT.Address a on ca.AddressID = ca.AddressID
FOR XML RAW ('Customer'), ROOT ('Customers'), ELEMENTS XSINIL; 

