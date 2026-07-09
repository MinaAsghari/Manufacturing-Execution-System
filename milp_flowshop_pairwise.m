function milp_flowshop_pairwise()

% ---------- CONFIG ----------
cfg.server   = "localhost";
cfg.port     = 1433;
cfg.database = "DIBRIS_BIKE";
cfg.user     = "sa";
cfg.password = "SqlServer!123";

batch_id = 1;

% ---------- READ ----------
conn = mssql_connect(cfg);

sql = sprintf(['SELECT id, processing_time_on_welding, processing_time_on_oven ' ...
               'FROM dbo.cutted_tubes WHERE batch_id = %d ORDER BY id;'], batch_id);

tubes = mssql_query(conn, sql);
conn.jconn.close();

ids = tubes(:,1);
A   = tubes(:,2); % M1
B   = tubes(:,3); % M2
n   = numel(ids);

fprintf("MILP (pairwise) for n=%d\n", n);

% ---------- VARIABLES ----------
% y(i,j) binary: i before j
Y = n*n;

S1 = n;
S2 = n;
Cmax = 1;

total = Y + S1 + S2 + Cmax;

Y_idx  = 1:Y;
S1_idx = Y + (1:n);
S2_idx = Y + n + (1:n);
C_idx  = total;

% ---------- OBJECTIVE ----------
f = zeros(total,1);
f(C_idx) = 1;

intcon = Y_idx;

lb = zeros(total,1);
ub = ones(total,1);

ub(S1_idx) = inf;
ub(S2_idx) = inf;
ub(C_idx)  = inf;

% ---------- CONSTRAINTS ----------
Aineq = [];
bineq = [];

M = sum(A+B); % big-M

% sequencing constraints
for i=1:n
    for j=1:n
        if i==j, continue; end

        % S1_j >= S1_i + A_i - M*(1 - y_ij)
        row=zeros(1,total);
        row(S1_idx(j)) = 1;
        row(S1_idx(i)) = -1;
        row((j-1)*n + i) = -M;
        Aineq=[Aineq; row];
        bineq=[bineq; -A(i)+M];

        % S2_j >= S2_i + B_i - M*(1 - y_ij)
        row=zeros(1,total);
        row(S2_idx(j)) = 1;
        row(S2_idx(i)) = -1;
        row((j-1)*n + i) = -M;
        Aineq=[Aineq; row];
        bineq=[bineq; -B(i)+M];
    end
end

% machine order (M2 بعد از M1)
for i=1:n
    row=zeros(1,total);
    row(S2_idx(i)) = 1;
    row(S1_idx(i)) = -1;
    Aineq=[Aineq; row];
    bineq=[bineq; -A(i)];
end

% makespan
for i=1:n
    row=zeros(1,total);
    row(C_idx) = -1;
    row(S2_idx(i)) = 1;
    Aineq=[Aineq; row];
    bineq=[bineq; -B(i)];
end

% antisymmetry: y_ij + y_ji = 1
Aeq=[];
beq=[];
for i=1:n
    for j=i+1:n
        row=zeros(1,total);
        row((j-1)*n + i)=1;
        row((i-1)*n + j)=1;
        Aeq=[Aeq;row];
        beq=[beq;1];
    end
end

% ---------- SOLVE ----------
opts = optimoptions('intlinprog','Display','off');
[x,fval] = intlinprog(f,intcon,Aineq,bineq,Aeq,beq,lb,ub,opts);

fprintf("MILP Makespan: %.0f\n", fval);

% ---------- EXTRACT ORDER ----------
Ymat = reshape(x(Y_idx),[n,n]);

score = sum(Ymat,2); % تعداد jobهایی که قبلش هستن
[~,order] = sort(score);

seq = ids(order);

fprintf("MILP sequence: ");
fprintf("%d ",seq);
fprintf("\n");

% ---------- JOHNSON ----------
jIdx = johnson_order(A,B);
jMs  = makespan_2machine(A(jIdx),B(jIdx));

fprintf("Johnson Makespan: %d\n", jMs);

if abs(jMs - fval) < 1e-6
    fprintf("MATCH ✅\n");
else
    fprintf("NOT MATCH ❌\n");
end

end

% ===== HELPERS =====

function seqIdx = johnson_order(A,B)
n=numel(A);
rem=true(1,n);
front=[]; back=[];
for k=1:n
    idx=find(rem);
    [minA,ia]=min(A(idx));
    [minB,ib]=min(B(idx));
    if minA<=minB
        j=idx(ia); front(end+1)=j;
    else
        j=idx(ib); back(end+1)=j;
    end
    rem(j)=false;
end
seqIdx=[front fliplr(back)];
end

function Cmax = makespan_2machine(A,B)
e1=0; e2=0;
for i=1:numel(A)
    e1=e1+A(i);
    e2=max(e2,e1)+B(i);
end
Cmax=e2;
end

function conn = mssql_connect(cfg)
jdbcUrl = sprintf("jdbc:sqlserver://%s:%d;databaseName=%s;encrypt=false;trustServerCertificate=true;", ...
    cfg.server,cfg.port,cfg.database);
props = java.util.Properties();
props.setProperty("user",cfg.user);
props.setProperty("password",cfg.password);
conn.jconn = java.sql.DriverManager.getConnection(jdbcUrl, props);
end

function data = mssql_query(conn, sql)
stmt = conn.jconn.createStatement();
rs = stmt.executeQuery(sql);
md = rs.getMetaData();
ncol = md.getColumnCount();
rows={};
while rs.next()
    r=zeros(1,ncol);
    for c=1:ncol
        r(c)=rs.getLong(c);
    end
    rows{end+1,1}=r;
end
rs.close(); stmt.close();
if isempty(rows)
    data=zeros(0,ncol);
else
    data=vertcat(rows{:});
end
end