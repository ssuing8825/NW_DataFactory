IF OBJECT_ID('dbo.customerxml', 'U') IS NOT NULL 
  DROP TABLE dbo.customerxml; 

CREATE TABLE dbo.customerxml (
    Xml_id INT PRIMARY KEY IDENTITY (1, 1),
    customerxml xml NOT NULL,
    batchid VARCHAR (50) NOT NULL,
    clientBatchId VARCHAR (50) NOT NULL,
);