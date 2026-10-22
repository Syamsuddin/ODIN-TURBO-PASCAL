#!/usr/bin/env python3
"""Acuan NumPy independen untuk unit tambahan; tidak diperlukan saat memakai Pascal."""
from pathlib import Path
import os
import subprocess
import numpy as np
root=Path(__file__).resolve().parents[1]
binary=Path(os.environ.get('TPAI_ORACL2',str(root/'BIN'/'ORACL2')))
if os.name=='nt' and binary.suffix.lower()!='.exe':binary=binary.with_suffix('.exe')
lines=subprocess.run([str(binary)],cwd=root,text=True,capture_output=True,check=True).stdout.splitlines()
values={}; iw=np.zeros((2,2)); hb=np.zeros(2); ow=np.zeros(2); tf={}
for line in lines:
    t=line.split()
    if t[0]=='NNW':iw[int(t[1])-1,int(t[2])-1]=float(t[3])
    elif t[0]=='NNB':hb[int(t[1])-1]=float(t[2])
    elif t[0]=='NNO':ow[int(t[1])-1]=float(t[2])
    elif t[0]=='TFIDF':tf[t[1]]=float(t[2])
    elif t[0]=='ABI':print(line)
    else:values[t[0]]=float(t[1])
checks=0
def check(actual,expected,name):
    global checks
    np.testing.assert_allclose(actual,expected,atol=2e-7,rtol=2e-7)
    checks+=1; print('PASS '+name)
def sigmoid(x):return 1/(1+np.exp(-x))
x=np.array([[-2.,1.],[1.,3.],[2.,-1.]])
y=np.array([0.,1.,1.])
w=-0.2*(x.T@(np.full(3,.5)-y))/3
b=-0.2*(.5-y).mean()
check([values['LOGW1'],values['LOGW2']],w,'Logistic batch gradient')
check(values['LOGB'],b,'Logistic bias')
z=x@w+b
check(values['LOGL'],np.mean(np.logaddexp(0,z)-y*z),'Logistic BCE')
# Park-Miller seed reproduced to compare one entire backprop epoch.
state=42
def rnd():
    global state
    state=(16807*state)%2147483647
    return state/2147483647
wi=np.array([2*rnd()-1 for _ in range(4)]).reshape(2,2)*np.sqrt(6/4)
wo=np.array([2*rnd()-1 for _ in range(2)])*np.sqrt(6/3)
bh=np.zeros(2); bo=0.
order=list(range(3))
for i in range(2,0,-1):
    j=int(rnd()*(i+1)); order[i],order[j]=order[j],order[i]
for row in order:
    a=sigmoid(wi@x[row]+bh); e=sigmoid(wo@a+bo)-y[row]
    dh=e*wo*a*(1-a)
    wo-=.1*e*a; wi-=.1*np.outer(dh,x[row]); bh-=.1*dh; bo-=.1*e
check(iw,wi,'Neural backprop input weights')
check(hb,bh,'Neural backprop hidden bias')
check(ow,wo,'Neural backprop output weights')
check(values['NNOB'],bo,'Neural backprop output bias')
z=sigmoid(x@wi.T+bh)@wo+bo
check(values['NNLOSS'],np.mean(np.logaddexp(0,z)-y*z),'Neural BCE after epoch')
query=np.array([.2,1.1]); scores=[]
for c in range(2):
    subset=x[y==c]; var=np.maximum(subset.var(axis=0),.1)
    scores.append(np.log(len(subset)/len(x))-.5*np.sum(np.log(2*np.pi*var)+(query-subset.mean(axis=0))**2/var))
def softmax(a):
    a=np.asarray(a); e=np.exp(a-a.max()); return e/e.sum()
check([values['GAUSS0'],values['GAUSS1']],softmax(scores),'Gaussian log posterior')
counts=np.array([[3.,1.],[1.,4.],[2.,5.]])
scores=[]
for c in range(2):
    v=counts[y==c].sum(axis=0)+.5; scores.append(np.log(np.mean(y==c))+np.log(v/v.sum())@np.array([2,1]))
check([values['MULT0'],values['MULT1']],softmax(scores),'Multinomial smoothed posterior')
idf=np.log(4/np.array([3.,3.,2.]))+1
v=np.array([2,0,1])*idf;v/=np.linalg.norm(v)
check([tf['apel'],tf['pisang'],tf['jeruk']],v,'TF-IDF smoothed L2 vector')
def tri(x,a,b,c):
    x=np.asarray(x); result=np.zeros_like(x,dtype=float)
    if b>a:result=np.where((x>a)&(x<b),(x-a)/(b-a),result)
    if c>b:result=np.where((x>b)&(x<c),(c-x)/(c-b),result)
    return np.where(x==b,1.,result)
temp=[(0,0,20),(10,20,30),(20,40,40)]
hum=[(0,0,50),(25,50,75),(50,100,100)]
grid=np.linspace(0,100,401); agg=np.zeros_like(grid)
for i in range(3):
    for j in range(3):
        strength=min(float(tri(28,*temp[i])),float(tri(70,*hum[j])))
        out=i+1 if j==2 and i<2 else i
        agg=np.maximum(agg,np.minimum(strength,tri(grid,*hum[out])))
weights=np.ones_like(grid);weights[[0,-1]]=.5
check(values['FUZZY'],np.sum(weights*grid*agg)/np.sum(weights*agg),'Mamdani centroid quadrature')
q=.7+.3*(-1+.9*4-.7)
check(values['QSTEP'],q,'Q-learning Bellman step')
check(values['QTERM'],q+.3*(10-q),'Q-learning terminal step')
print(f'TOTAL NUMPY ADV PASS={checks} FAIL=0')
