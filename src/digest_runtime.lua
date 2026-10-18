local M = {}
local names = require("src.names")

function M.source(rand)
    local source = [[
local dgK={}
local dgRoundConstantsHex='428a2f9871374491b5c0fbcfe9b5dba53956c25b59f111f1923f82a4ab1c5ed5d807aa9812835b01243185be550c7dc372be5d7480deb1fe9bdc06a7c19bf174e49b69c1efbe47860fc19dc6240ca1cc2de92c6f4a7484aa5cb0a9dc76f988da983e5152a831c66db00327c8bf597fc7c6e00bf3d5a7914706ca63511429296727b70a852e1b21384d2c6dfc53380d13650a7354766a0abb81c2c92e92722c85a2bfe8a1a81a664bc24b8b70c76c51a3d192e819d6990624f40e3585106aa07019a4c1161e376c082748774c34b0bcb5391c0cb34ed8aa4a5b9cca4f682e6ff3748f82ee78a5636f84c878148cc7020890befffa a4506cebbe f9a3f7c67178f2'
dgRoundConstantsHex=dgRoundConstantsHex:gsub('%s','')
local function dgN(s)local n=0;for i=1,#s do local b=s:byte(i);local d=b>=48 and b<=57 and b-48 or b>=97 and b-87 or b-55;n=n*16+d end;return n end
for i=1,64 do dgK[i]=dgN(dgRoundConstantsHex:sub(i*8-7,i*8)) end
local function dgR(x,n)return((x>>n)|((x<<(32-n))&0xFFFFFFFF))&0xFFFFFFFF end
local function dgRaw(s)
local n=#s*8;local p=56-((#s+1)%64);if p<0 then p=p+64 end;local hi=(n>>32)&0xFFFFFFFF;local lo=n&0xFFFFFFFF;s=s..string.char(128)..string.rep('\0',p)..string.pack('>I4I4',hi,lo)
local a0,b0,c0,d0,e0,f0,g0,h0=0x6A09E667,0xBB67AE85,0x3C6EF372,0xA54FF53A,0x510E527F,0x9B05688C,0x1F83D9AB,0x5BE0CD19
local w={}
for o=1,#s,64 do
for i=1,16 do w[i]=string.unpack('>I4',s,o+(i-1)*4) end
for i=17,64 do local x=w[i-15];local y=w[i-2];w[i]=(w[i-16]+(dgR(x,7)~dgR(x,18)~(x>>3))+w[i-7]+(dgR(y,17)~dgR(y,19)~(y>>10)))&0xFFFFFFFF end
local a,b,c,d,e,f,g,h=a0,b0,c0,d0,e0,f0,g0,h0
for i=1,64 do local s1=dgR(e,6)~dgR(e,11)~dgR(e,25);local ch=(e&f)~((~e)&g);local t1=(h+s1+ch+dgK[i]+w[i])&0xFFFFFFFF;local s2=dgR(a,2)~dgR(a,13)~dgR(a,22);local mj=(a&b)~(a&c)~(b&c);local t2=(s2+mj)&0xFFFFFFFF;h,g,f,e=g,f,e,(d+t1)&0xFFFFFFFF;d,c,b,a=c,b,a,(t1+t2)&0xFFFFFFFF end
a0,b0,c0,d0,e0,f0,g0,h0=(a0+a)&0xFFFFFFFF,(b0+b)&0xFFFFFFFF,(c0+c)&0xFFFFFFFF,(d0+d)&0xFFFFFFFF,(e0+e)&0xFFFFFFFF,(f0+f)&0xFFFFFFFF,(g0+g)&0xFFFFFFFF,(h0+h)&0xFFFFFFFF
end
return string.pack('>I4I4I4I4I4I4I4I4',a0,b0,c0,d0,e0,f0,g0,h0)
end
local function dgHex(s)local t={};for i=1,#s do t[i]=string.format('%02x',s:byte(i)) end;return table.concat(t) end
local function dgHmac(k,s)
if #k>64 then k=dgRaw(k) end;k=k..string.rep('\0',64-#k);local i,o={},{};for n=1,64 do local b=k:byte(n);i[n]=string.char(b~0x36);o[n]=string.char(b~0x5C) end;return dgHex(dgRaw(table.concat(o)..dgRaw(table.concat(i)..s)))
end
local function dgEq(a,b)if #a~=#b then return false end;local x=0;for i=1,#a do x=x|(a:byte(i)~b:byte(i)) end;return x==0 end
]]
    if rand == nil then
        return source, {
            dgRaw = "dgRaw",
            dgHex = "dgHex",
            dgHmac = "dgHmac",
            dgEq = "dgEq"
        }
    end
    local used = {
        P = true, I = true, H = true, A = true, B = true, Z = true,
        X1 = true, X2 = true, X3 = true, X4 = true, X5 = true, X6 = true,
        E = true, Q = true, V = true, W = true, string = true, table = true,
    }
    local nextName = names.new("random", rand, used)
    local order = { "dgK", "dgRoundConstantsHex", "dgN", "dgR", "dgRaw", "dgHex", "dgHmac", "dgEq" }
    local replacements = {
        dgK = nextName(),
        dgRoundConstantsHex = nextName(),
        dgN = nextName(),
        dgR = nextName(),
        dgRaw = nextName(),
        dgHex = nextName(),
        dgHmac = nextName(),
        dgEq = nextName()
    }
    for _, original in ipairs(order) do
        source = source:gsub("%f[%w_]" .. original .. "%f[^%w_]", replacements[original])
    end
    return source, replacements
end

return M
