function run_ex2()
% Exercise 2: Read tubes from SQL -> Johnson schedule -> write results to SQL

% ---------- Connection settings ----------
cfg.server   = "localhost";
cfg.port     = 1433;
cfg.database = "DIBRIS_BIKE";
cfg.user     = "sa";
cfg.password = "SqlServer!123";

batch_id = 1; % مشخص میکنه روی کدوم بج داری کار میکنی. می‌تونی عوض کنی

% 1) Connect
conn = mssql_connect(cfg);

% 2) اگر برای این بج داده نداریم، چند داده نمونه وارد کن
seed_if_empty(conn, batch_id);

% 3) Read tubes
sql = sprintf( ...
    "SELECT id, batch_id, processing_time_on_welding, processing_time_on_oven " + ...
    "FROM dbo.cutted_tubes WHERE batch_id = %d ORDER BY id;", batch_id);

tubes = mssql_query(conn, sql); % کویری اجرا میشه و داده ها دریافت میشه

% جدا کردن ستون ها از هم
ids = tubes(:,1);
A   = tubes(:,3); % welding time
B   = tubes(:,4); % oven time

% 4) Johnson order که بهترین ترتیب انجام جاب ها را پیدا می کنه
seqIdx     = johnson_order(A, B);   % indices (rows)
seqTubeIds = ids(seqIdx); % ترتیب واقعی تیوب ها
Aseq       = A(seqIdx); % زمان های مرتب شده براساس ترتیب جدید
Bseq       = B(seqIdx);

% 5) Timing on 2 machines
[s1, e1, s2, e2, makespan] = two_machine_timing(Aseq, Bseq);

% 6) Store schedule در جدول جانسون ذخیره میشه
store_schedule(conn, batch_id, seqTubeIds, s1, e1, s2, e2, makespan);

% 7) Print summary
disp("Johnson sequence (tube_id):");
disp(seqTubeIds.');

fprintf("Makespan = %d\n", makespan);

% Close اتصال ددیتا بیس بسته میشه
mssql_close(conn);
end

% === SQL helpers (JDBC) ===

function conn = mssql_connect(cfg)% ساخت آدرس برای اتصال اس کیو ال به متلب
jdbcUrl = sprintf( ...
    "jdbc:sqlserver://%s:%d;databaseName=%s;encrypt=false;trustServerCertificate=true;", ...
    cfg.server, cfg.port, cfg.database);


props = java.util.Properties(); % تنظیمات اتصال
props.setProperty("user", cfg.user);
props.setProperty("password", cfg.password);

conn.jconn = java.sql.DriverManager.getConnection(jdbcUrl, props); % اتصال واقعی
end

function mssql_close(conn)
conn.jconn.close(); % بستن اتصال
end

function data = mssql_query(conn, sql)
stmt = conn.jconn.createStatement(); % اجرای کویری
rs = stmt.executeQuery(sql); % ذخیره میشه
md = rs.getMetaData(); %  اطلاعات شامل تعداد ستون‌ها، نام ستون‌ها را میگیرد
ncol = md.getColumnCount(); % تعداد ستون های جدول

rows = {};
while rs.next() % روی تمام ردیف های نتیجه لوپ میزنه
    r = zeros(1, ncol); % یک آرایه می سازد
    for c = 1:ncol
        r(c) = rs.getLong(c); % داده هر ستون رو میخونه
    end
    rows{end+1,1} = r; %#ok<AGROW>
end
rs.close(); stmt.close();

if isempty(rows)
    data = zeros(0, ncol);
else
    data = vertcat(rows{:}); % همه ردیف ها رو به ماتریس متلب تبدیل می کنه
end
end

function mssql_exec(conn, sql) % برای کویری هایی که خروجی ندارند
stmt = conn.jconn.createStatement();
stmt.execute(sql);
stmt.close();
end

function seed_if_empty(conn, batch_id) % چک می کند آیا داده ای وجود دارد یا نه
checkSql = sprintf("SELECT COUNT(*) FROM dbo.cutted_tubes WHERE batch_id=%d;", batch_id);
c = mssql_query(conn, checkSql);

if c(1) > 0
    return;
end

% اگر داده نبود داده ی تستی می سازد
demo = [ ...
    5  9
    7  4
    3  8
    9  6
    4  7
    8  5 ]; % ستون اول زمان ماشین یک ستون دوم ماشین دو

for i = 1:size(demo,1) % اینجا داخل اس کیو ال ذخیره میکنه
    A = demo(i,1); B = demo(i,2);
    ins = sprintf( ...
        "INSERT INTO dbo.cutted_tubes (batch_id, processing_time_on_welding, processing_time_on_oven) " + ...
        "VALUES (%d, %d, %d);", batch_id, A, B);
    mssql_exec(conn, ins);
end

fprintf("Seeded %d tubes into cutted_tubes for batch_id=%d\n", size(demo,1), batch_id);
end

% === Johnson + timing ===

function seqIdx = johnson_order(A, B) % قانون جانسون برای دو ماشین
n = numel(A);
remaining = true(1,n); % 
front = [];
back  = [];

for k = 1:n
    idx = find(remaining);
    [minA, ia] = min(A(idx)); % انتخاب کمترین زمان بین دو ماشین
    [minB, ib] = min(B(idx));

    if minA <= minB
        j = idx(ia);
        front(end+1) = j; %#ok<AGROW>
    else
        j = idx(ib);
        back(end+1) = j; %#ok<AGROW>
    end
    remaining(j) = false; % حذف جاب انتخاب شده
end

seqIdx = [front, fliplr(back)]; % ترتیب نهایی ساخته میشود
end

function [s1, e1, s2, e2, makespan] = two_machine_timing(Aseq, Bseq)
n = numel(Aseq);
s1 = zeros(n,1); e1 = zeros(n,1);
s2 = zeros(n,1); e2 = zeros(n,1);

for i = 1:n % محاسبه زمان بندی با استفاده از قانون فلوشاپ
    if i == 1
        s1(i) = 0;
    else
        s1(i) = e1(i-1);
    end
    e1(i) = s1(i) + Aseq(i);

    if i == 1
        s2(i) = e1(i);
    else
        s2(i) = max(e1(i), e2(i-1)); % جاب ماشتن اول نمام و ماشین دوم آزاد باشد
    end
    e2(i) = s2(i) + Bseq(i); % زمان پایان روی ماشین دوم محاسبه می‌شود
end

makespan = e2(end);
end

function store_schedule(conn, batch_id, tubeIds, s1, e1, s2, e2, makespan)
% Delete previous schedule rows for this batch
del = sprintf("DELETE FROM dbo.johnson_schedule WHERE batch_id=%d;", batch_id);
mssql_exec(conn, del);

n = numel(tubeIds);
for pos = 1:n
    ins = sprintf( ...
        "INSERT INTO dbo.johnson_schedule " + ...
        "(batch_id, tube_id, sequence_pos, machine1_start, machine1_end, machine2_start, machine2_end, makespan) " + ...
        "VALUES (%d, %d, %d, %d, %d, %d, %d, %d);" , ...
        batch_id, tubeIds(pos), pos, s1(pos), e1(pos), s2(pos), e2(pos), makespan);
    mssql_exec(conn, ins);
end
end