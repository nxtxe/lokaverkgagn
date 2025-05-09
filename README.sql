-- 1. Tafla með flokkunum, notendagerðum og stöðum
CREATE TABLE ProblemCategory (
    CategoryID SERIAL PRIMARY KEY,
    CategoryName VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE UserType (
    TypeID SERIAL PRIMARY KEY,
    TypeName VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE UserStatus (
    StatusID SERIAL PRIMARY KEY,
    StatusName VARCHAR(50) NOT NULL UNIQUE
);

-- 2. Notendatafla
CREATE TABLE "User" (
    UserID SERIAL PRIMARY KEY,
    Username VARCHAR(50) NOT NULL UNIQUE,
    PasswordHash CHAR(64) NOT NULL,
    FullName VARCHAR(100),
    Email VARCHAR(100) UNIQUE,
    TypeID INT NOT NULL REFERENCES UserType(TypeID),
    StatusID INT NOT NULL REFERENCES UserStatus(StatusID),
    CreatedAt TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 3. Spurninga- og lausnataflur
CREATE TABLE Problem (
    ProblemID SERIAL PRIMARY KEY,
    PostedBy INT NOT NULL REFERENCES "User"(UserID),
    CategoryID INT NOT NULL REFERENCES ProblemCategory(CategoryID),
    Title VARCHAR(200) NOT NULL,
    Description TEXT NOT NULL,
    CreatedAt TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE Solution (
    SolutionID SERIAL PRIMARY KEY,
    ProblemID INT NOT NULL REFERENCES Problem(ProblemID) ON DELETE CASCADE,
    PostedBy INT NOT NULL REFERENCES "User"(UserID),
    Content TEXT NOT NULL,
    CreatedAt TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 4. Eiginleikamat fyrir lausnir
CREATE TABLE Rating (
    UserID INT NOT NULL REFERENCES "User"(UserID),
    SolutionID INT NOT NULL REFERENCES Solution(SolutionID),
    Score INT NOT NULL CHECK (Score BETWEEN 1 AND 10),
    RatedAt TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY(UserID, SolutionID)
);

-- 5. Sjálfgefin gögn fyrir flokkun og stöður
INSERT INTO ProblemCategory (CategoryName) VALUES
('Forritun'), ('Gagnagrunnar'), ('Leikjaforritun'), ('Kerfisstjórnun - Linux'),
('Kerfisstjórnun - Windows'), ('Róbótar'), ('Vefþróun'), ('Annað');

INSERT INTO UserType (TypeName) VALUES
('byrjandi'), ('hefðbundinn'), ('lengra kominn'), ('súpernotandi'), ('admin');

INSERT INTO UserStatus (StatusName) VALUES
('Virkur'), ('Óvirkur'), ('Tímabundið bann'), ('Bann');

-- 6. CRUD fyrir flokk
CREATE OR REPLACE FUNCTION ListCategories() RETURNS TABLE(CategoryID INT, CategoryName VARCHAR) AS $$
BEGIN RETURN QUERY SELECT CategoryID, CategoryName FROM ProblemCategory; END;
$$;

CREATE OR REPLACE FUNCTION GetCategory(p_id INT) RETURNS TABLE(CategoryID INT, CategoryName VARCHAR) AS $$
BEGIN RETURN QUERY SELECT CategoryID, CategoryName FROM ProblemCategory WHERE CategoryID = p_id; END;
$$;

CREATE OR REPLACE FUNCTION AddCategory(p_name VARCHAR) RETURNS VOID AS $$
BEGIN INSERT INTO ProblemCategory(CategoryName) VALUES (p_name); END;
$$;

CREATE OR REPLACE FUNCTION UpdateCategory(p_id INT, p_name VARCHAR) RETURNS VOID AS $$
BEGIN UPDATE ProblemCategory SET CategoryName = p_name WHERE CategoryID = p_id; END;
$$;

CREATE OR REPLACE FUNCTION DeleteCategory(p_id INT) RETURNS VOID AS $$
BEGIN DELETE FROM ProblemCategory WHERE CategoryID = p_id; END;
$$;

-- 7. CRUD fyrir notendur
CREATE OR REPLACE FUNCTION ListUsers() RETURNS TABLE(UserID INT, Username VARCHAR, FullName VARCHAR, Email VARCHAR, TypeID INT, StatusID INT) AS $$
BEGIN RETURN QUERY SELECT UserID, Username, FullName, Email, TypeID, StatusID FROM "User"; END;
$$;

CREATE OR REPLACE FUNCTION GetUser(p_id INT) RETURNS TABLE(UserID INT, Username VARCHAR, FullName VARCHAR, Email VARCHAR, TypeID INT, StatusID INT) AS $$
BEGIN RETURN QUERY SELECT UserID, Username, FullName, Email, TypeID, StatusID FROM "User" WHERE UserID = p_id; END;
$$;

CREATE OR REPLACE FUNCTION AddUser(p_username VARCHAR, p_hash CHAR(64), p_fullname VARCHAR, p_email VARCHAR, p_type INT, p_status INT) RETURNS VOID AS $$
BEGIN INSERT INTO "User"(Username, PasswordHash, FullName, Email, TypeID, StatusID) VALUES (p_username, p_hash, p_fullname, p_email, p_type, p_status); END;
$$;

CREATE OR REPLACE FUNCTION UpdateUser(p_id INT, p_fullname VARCHAR, p_email VARCHAR) RETURNS VOID AS $$
BEGIN UPDATE "User" SET FullName = p_fullname, Email = p_email WHERE UserID = p_id AND StatusID = (SELECT StatusID FROM UserStatus WHERE StatusName='Virkur'); END;
$$;

CREATE OR REPLACE FUNCTION DeleteUser(p_id INT) RETURNS VOID AS $$
DECLARE cnt INT;
BEGIN
    SELECT COUNT(*) INTO cnt FROM Problem WHERE PostedBy = p_id;
    cnt := cnt + (SELECT COUNT(*) FROM Solution WHERE PostedBy = p_id);
    IF cnt = 0 THEN
        DELETE FROM "User" WHERE UserID = p_id;
    ELSE
        UPDATE "User" SET StatusID = (SELECT StatusID FROM UserStatus WHERE StatusName = 'Óvirkur') WHERE UserID = p_id;
    END IF;
END;
$$;

-- 8. Kjarnavirkni
CREATE OR REPLACE FUNCTION PostProblem(p_user INT, p_category INT, p_title VARCHAR, p_desc TEXT) RETURNS VOID AS $$
BEGIN
    IF (SELECT StatusName FROM UserStatus us JOIN "User" u ON us.StatusID = u.StatusID WHERE u.UserID = p_user) <> 'Virkur' THEN
        RAISE EXCEPTION 'Notandi er óvirkur eða bannaður';
    END IF;
    INSERT INTO Problem(PostedBy, CategoryID, Title, Description) VALUES(p_user, p_category, p_title, p_desc);
END;
$$;

CREATE OR REPLACE FUNCTION PostSolution(p_user INT, p_problem INT, p_content TEXT) RETURNS VOID AS $$
BEGIN
    IF (SELECT StatusName FROM UserStatus us JOIN "User" u ON us.StatusID = u.StatusID WHERE u.UserID = p_user) <> 'Virkur' THEN
        RAISE EXCEPTION 'Notandi er óvirkur eða bannaður';
    END IF;
    INSERT INTO Solution(ProblemID, PostedBy, Content) VALUES(p_problem, p_user, p_content);
END;
$$;

CREATE OR REPLACE FUNCTION AdminUpdateStatus(p_admin INT, p_user INT, p_newstatus INT) RETURNS VOID AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM "User" u JOIN UserType ut ON u.TypeID = ut.TypeID WHERE u.UserID = p_admin AND ut.TypeName = 'admin') THEN
        RAISE EXCEPTION 'Aðeins stjórnendur mega uppfæra stöðu';
    END IF;
    UPDATE "User" SET StatusID = p_newstatus WHERE UserID = p_user;
END;
$$;

CREATE OR REPLACE FUNCTION ListSolutions(p_problem INT) RETURNS TABLE(SolutionID INT, PostedBy INT, Content TEXT, CreatedAt TIMESTAMP) AS $$
BEGIN
    RETURN QUERY SELECT SolutionID, PostedBy, Content, CreatedAt FROM Solution WHERE ProblemID = p_problem ORDER BY CreatedAt;
END;
$$;

CREATE OR REPLACE FUNCTION CountUserProblems(p_user INT) RETURNS INT AS $$
DECLARE cnt INT;
BEGIN SELECT COUNT(*) INTO cnt FROM Problem WHERE PostedBy = p_user; RETURN cnt; END;
$$;

CREATE OR REPLACE FUNCTION IsAdmin(p_user INT) RETURNS BOOLEAN AS $$
DECLARE tname TEXT;
BEGIN SELECT ut.TypeName INTO tname FROM UserType ut JOIN "User" u ON ut.TypeID = u.TypeID WHERE u.UserID = p_user; RETURN tname = 'admin'; END;
$$;

CREATE OR REPLACE FUNCTION SolutionStats(p_solution INT) RETURNS TABLE(AverageScore NUMERIC, CountRatings INT, MedianScore NUMERIC) AS $$
BEGIN
    RETURN QUERY SELECT AVG(Score)::NUMERIC(5,2), COUNT(*), PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Score) FROM Rating WHERE SolutionID = p_solution;
END;
$$;

-- 9. Gildra fyrir sjálfvirka uppfærslu á notendagerð
CREATE OR REPLACE FUNCTION trg_upgrade_user_type() RETURNS TRIGGER AS $$
DECLARE total_posts INT;
BEGIN
    SELECT (SELECT COUNT(*) FROM Problem WHERE PostedBy = NEW.PostedBy) + (SELECT COUNT(*) FROM Solution WHERE PostedBy = NEW.PostedBy) INTO total_posts;
    IF (SELECT TypeName FROM UserType WHERE TypeID = (SELECT TypeID FROM "User" WHERE UserID = NEW.PostedBy)) = 'byrjandi'
       AND total_posts > 20 THEN
        UPDATE "User" SET TypeID = (SELECT TypeID FROM UserType WHERE TypeName = 'hefðbundinn') WHERE UserID = NEW.PostedBy;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER UpgradeBeginner AFTER INSERT ON Solution FOR EACH ROW EXECUTE FUNCTION trg_upgrade_user_type();
