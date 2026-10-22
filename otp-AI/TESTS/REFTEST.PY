#!/usr/bin/env python3
"""Pembanding independen NumPy. Jalankan dari root otp-AI setelah build ORACLE.
Kebutuhan tambahan hanya untuk verifikasi pengembang: Python 3 dan NumPy.
Program Pascal sendiri tidak memerlukan Python.
"""
from pathlib import Path
import csv
import os
import subprocess
import numpy as np

root = Path(__file__).resolve().parents[1]
binary = Path(os.environ.get('TPAI_ORACLE', str(root/'BIN'/'ORACLE')))
if os.name == 'nt' and binary.suffix.lower() != '.exe':
    binary = binary.with_suffix('.exe')
fixture = root/'DATA'/'ORACLE.CSV'
original = fixture.read_bytes() if fixture.exists() else None
checks = 0
try:
    for seed in range(6):
        rng = np.random.default_rng(seed)
        x = rng.normal(size=(50,4))
        beta = np.array([2.5,-1.2,.4,3.1])
        y = 4.25+x@beta+rng.normal(scale=.15,size=50)
        ridge = 0.0 if seed % 2 == 0 else .25
        with fixture.open('w', newline='') as handle:
            writer = csv.writer(handle)
            writer.writerow(['X1','X2','X3','X4','Y'])
            writer.writerows([[f'{v:.9f}' for v in row] for row in np.column_stack([x,y])])
        # Acuan memakai angka yang benar-benar disimpan, bukan angka sebelum pembulatan.
        table = np.loadtxt(fixture,delimiter=',',skiprows=1)
        x,y = table[:,:-1],table[:,-1]
        run = subprocess.run([str(binary), str(ridge)],cwd=root,text=True,capture_output=True,check=True)
        coef = np.zeros(5); pred = np.zeros(5); knn = np.zeros(5)
        centers = np.zeros((3,4)); labels = np.zeros(50,dtype=int); history=[]
        for line in run.stdout.splitlines():
            t=line.split()
            if t[0]=='COEF':coef[int(t[1])]=float(t[2])
            elif t[0]=='PRED':pred[int(t[1])-1]=float(t[2])
            elif t[0]=='KNN':knn[int(t[1])-1]=float(t[2])
            elif t[0]=='CENTER':centers[int(t[1])-1,int(t[2])-1]=float(t[3])
            elif t[0]=='LABEL':labels[int(t[1])-1]=int(t[2])-1
            elif t[0]=='INERTIA':inertia=float(t[1])
            elif t[0]=='HISTORY':history.append(float(t[2]))
        if ridge==0:
            expected = np.linalg.lstsq(np.column_stack([np.ones(50),x]),y,rcond=None)[0]
        else:
            mean=x.mean(axis=0); scale=x.std(axis=0); z=(x-mean)/scale
            weights=np.linalg.solve(z.T@z+ridge*np.eye(4),z.T@(y-y.mean()))/scale
            expected=np.r_[y.mean()-weights@mean,weights]
        np.testing.assert_allclose(coef,expected,rtol=1e-6,atol=1e-6);checks+=1
        query=x[:5]+.11
        np.testing.assert_allclose(pred,np.c_[np.ones(5),query]@expected,rtol=1e-6,atol=1e-6);checks+=1
        nearest=np.argsort(((query[:,None,:]-x[None,:,:])**2).sum(axis=2),axis=1,kind='stable')[:,:5]
        np.testing.assert_allclose(knn,y[nearest].mean(axis=1),rtol=1e-6,atol=1e-6);checks+=1
        dist=((x[:,None,:]-centers[None,:,:])**2).sum(axis=2)
        np.testing.assert_array_equal(labels,dist.argmin(axis=1));checks+=1
        np.testing.assert_allclose(inertia,dist.min(axis=1).sum(),rtol=1e-6,atol=1e-6);checks+=1
        assert np.all(np.diff(history)<=1e-6);checks+=1
        print(f'PASS NumPy seed={seed}, ridge={ridge}, 6 pemeriksaan')
    print(f'TOTAL NUMPY PASS={checks} FAIL=0')
finally:
    if original is None:fixture.unlink(missing_ok=True)
    else:fixture.write_bytes(original)
