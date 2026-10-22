# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris

"""Build the Indonesian OTP-AI tutorial book PDF.

Optional authoring dependencies: PyMuPDF and Pillow. They are not runtime
dependencies of the Pascal units.
"""

from __future__ import annotations

import io
from pathlib import Path

import fitz
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "PANDUAN_OTP_AI.pdf"
FONT = Path("/System/Library/Fonts/Supplemental/Arial.ttf")
FONT_BOLD = Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf")
FONT_MONO = Path("/System/Library/Fonts/Menlo.ttc")
PAGE_W, PAGE_H = 595, 842
NAVY = (0.035, 0.075, 0.16)
INK = (0.10, 0.15, 0.25)
MUTED = (0.35, 0.41, 0.51)
TEAL = (0.02, 0.55, 0.53)
AMBER = (0.91, 0.49, 0.16)
PAPER = (0.985, 0.98, 0.95)
PALE = (0.91, 0.95, 0.95)
WHITE = (1, 1, 1)


TUTORIALS = [
    ("BASIC", "Matematika, matriks, dan statistik", "AIMATH + AISTATS",
     "Mulai dari operasi numerik yang menjadi dasar model AI. BASIC menunjukkan validasi input, matriks, dan ringkasan statistik tanpa dataset eksternal.",
     "MatrixMultiply", "Buat vektor dan matriks kecil; panggil fungsi; periksa Boolean; amati hasil yang dicetak.",
     ["Buka EXAMPLES/BASIC.PAS dan periksa klausa uses AIMATH serta AISTATS.",
      "Build BASIC.PAS dengan folder UNITS dan EXAMPLES pada search path.",
      "Run dari folder otp-AI; bandingkan jarak Euclidean, dot product, sigmoid, dan statistik.",
      "Ubah satu nilai input, build ulang, lalu jelaskan perubahan output."],
     "MatrixMultiply memakai output sementara: pemanggilan in-place aman dan hasil gagal tidak mengganti output."),
    ("DATAPREP", "Membaca, membagi, dan mempersiapkan data", "AIDATA + AISPLIT",
     "Pipeline data memisahkan nilai hilang, imputasi, dan scaling. Parameter preprocessing harus dipelajari dari data latih saja untuk mencegah data leakage.",
     "FitImputer", "DATAPREP membaca MISSING.CSV, membagi train/test, mengimputasi, menstandarkan, lalu menulis dua CSV.",
     ["Periksa DATA/MISSING.CSV dan tandai kolom yang kosong.",
      "Jalankan DATAPREP.PAS dari root otp-AI agar path DATA ditemukan.",
      "Periksa jumlah baris train/test dan pesan kategori one-hot.",
      "Buka PREPTRN.CSV serta PREPTST.CSV; pastikan keduanya memakai scaler train yang sama."],
     "FitImputer dan FitScaler menerima train; ImputeData dan TransformData menerapkan parameter yang sama ke train dan test."),
    ("REGDEMO", "Regresi linear satu fitur", "AIDATA + AISPLIT + AILINEAR + AISTATS + AIPLOT",
     "Pelajari alur supervised learning: holdout split, fit model pada train, prediksi test, dan ukur galat tanpa menyamakan korelasi dengan sebab-akibat.",
     "FitLinear", "REGDEMO memakai data sintetis JAMNILAI.CSV dan mencetak persamaan, MAE/RMSE, serta prediksi satu observasi.",
     ["Load JAMNILAI.CSV dan pastikan TargetReal digunakan.",
      "Pisahkan 75% train dan 25% test dengan seed tetap.",
      "FitLinear hanya pada train; evaluasi prediksi dengan target test.",
      "Ubah seed lalu bandingkan hasil; jangan menyebut data sintetis sebagai bukti kausal."],
     "MAE dan RMSE dinyatakan dalam satuan target; R2 hanya dicetak jika terdefinisi."),
    ("REGMULT", "Regresi multivariat dan koefisien", "AIDATA + AILINEAR + AISTATS",
     "REGMULT memulihkan persamaan buatan Y=5+2X1-3X2. Tujuannya memahami koefisien dan residual pada fixture yang dibuat deterministik.",
     "FitLinear", "Model linear menerima beberapa fitur; koefisien dapat dibaca dari Model.Coeff[1..Features].",
     ["Buka MULTIREG.CSV untuk melihat dua fitur dan satu target.",
      "Fit model dengan Ridge=0, lalu cetak intercept dan tiap koefisien.",
      "Bandingkan koefisien dengan persamaan pembentuk fixture.",
      "Ingat: RMSE latih pada data sintetis bukan ukuran generalisasi."],
     "Koefisien mendekati 2 dan -3 serta intercept 5 untuk data sintetis ini."),
    ("KNNDEMO", "K-nearest neighbors untuk klasifikasi", "AIDATA + AISPLIT + AIKNN + AISTATS + AIPLOT",
     "KNN menyimpan pointer ke dataset train. Scaling perlu di-fit pada train; dataset tersebut harus tetap hidup dan tidak berubah selama model dipakai.",
     "FitKNN", "Demo menggunakan fixture bunga sintetis, K=3, confusion matrix, metrik kelas, dan ekspor scatter SVG.",
     ["Load BUNGA.CSV dengan TargetClass dan lakukan split.",
      "Fit scaler pada train; transform train dan test dengan scaler yang sama.",
      "FitKNN pada train, lalu prediksi test dan hitung metrik.",
      "Buka KNN.SVG hasil run; contoh keluaran terdahulu tersedia di OUTPUT/KNN.SVG."],
     "Dataset contoh sintetis, bukan Iris. Lepaskan referensi model sebelum dataset train dibebaskan."),
    ("KMEANS", "Clustering tanpa label", "AIDATA + AIKMEANS + AIPLOT",
     "K-means membentuk kelompok berdasarkan jarak, bukan label target. Nomor cluster tidak mempunyai urutan mutu dan bukan kelas aktual.",
     "FitKMeans", "Contoh membandingkan pusat cluster dan inertia pada data geometris sintetis.",
     ["Buka DATA/CLUSTER.CSV dan catat bahwa cluster tidak disertai target kelas.",
      "Pilih K yang masuk akal dan seed agar run dapat diulang.",
      "FitKMeans, amati jumlah iterasi, status konvergensi, pusat dan inertia.",
      "Bandingkan K=2, 3, dan 4; lihat OUTPUT/INERTIA.SVG."],
     "Inertia adalah jumlah kuadrat jarak ke pusat terdekat; nilai lebih kecil tidak otomatis berarti model lebih baik."),
    ("CROSSVAL", "Validasi silang K-fold", "AIDATA + AISPLIT + AIKNN + AISTATS",
     "K-fold menggunakan setiap baris sebagai data uji tepat satu kali. Pipeline preprocessing dan model perlu di-fit ulang secara terpisah pada setiap fold.",
     "FoldSplit", "CROSSVAL membandingkan holdout dan beberapa fold dengan KNN pada fixture klasifikasi.",
     ["Atur jumlah fold dan seed; pilih Shuffle sesuai kebutuhan data.",
      "Panggil MakeFolds lalu FoldSplit untuk setiap fold.",
      "Fit transformasi/model hanya pada train fold, bukan keseluruhan dataset.",
      "Ringkas metrik fold; jangan menganggap fold acak sesuai untuk data berurutan waktu."],
     "AISPLIT tidak menyediakan stratifikasi kelas maupun time-series split."),
    ("LOGDEMO", "Regresi logistik", "AIDATA + AISPLIT + AILINEAR + AIOPTIM + AISTATS + AIPLOT",
     "Model logistik menghasilkan probabilitas kelas biner. Fungsi loss memakai BCE pada logit; parameter optimisasi dan stopping harus diperiksa.",
     "FitLogistic", "Demo melakukan split, scaling train, fit classifier, confusion matrix, dan membuat grafik loss.",
     ["Load fixture kelas biner dan pastikan label hanya 0/1.",
      "Fit scaler pada train; transform data train/test.",
      "Atur konfigurasi melalui DefaultTraining, lalu fit model dan periksa Info.",
      "Nilai probabilitas dan threshold menentukan kelas; amati LOGLOSS.SVG."],
     "Seed tidak mengubah batch logistic yang deterministik. Converged hanya True pada stop goal."),
    ("PERDEMO", "Perceptron dan batas linear", "AIDATA + AILINEAR + AIOPTIM",
     "Perceptron memperbarui bobot secara online dari kesalahan klasifikasi. AND dapat dipisahkan linear; XOR tidak bisa diselesaikan oleh satu perceptron.",
     "FitPerceptron", "Contoh memperlihatkan konvergensi AND dan keterbatasan XOR sebagai konsep, bukan bug implementasi.",
     ["Baca dataset AND dan XOR yang disediakan.",
      "Atur seed dan konfigurasi training agar urutan contoh berulang.",
      "FitPerceptron; periksa epochs, fraksi kesalahan, dan status konvergensi.",
      "Bandingkan tabel prediksi AND dan XOR; jangan menafsirkan score sebagai probabilitas."],
     "Converged berarti tidak ada salah klasifikasi pada data latih saat evaluasi akhir epoch."),
    ("NNDEMO", "Jaringan saraf kecil untuk XOR", "AIDATA + AINNET + AIOPTIM + AIMODEL + AIPLOT",
     "MLP OTP-AI adalah jaringan dense kecil dengan satu output biner. Contoh memudahkan melihat bobot, loss, stopping, prediksi, dan persistensi.",
     "FitNeural", "NNDEMO menggunakan XOR, empat neuron hidden, sigmoid, SGD online dan menyimpan XOR.TPM serta NNLOSS.SVG.",
     ["Buka XOR.CSV dan verifikasi empat kombinasi input.",
      "Ikuti konfigurasi Rate, Momentum, GoalLoss, Patience, MaxEpochs dan Seed.",
      "FitNeural; cek prediksi per baris dan Info.FinalLoss.",
      "Load model dari file hanya dengan compiler/ABI yang sama; lihat grafik loss."],
     "Model edukatif terbatas: tidak ada autodiff, mini-batch, dropout, CNN, RNN atau transformer."),
    ("BAYDEMO", "Naive Bayes Gaussian", "AIDATA + AISPLIT + AIBAYES + AISTATS",
     "Gaussian Naive Bayes memodelkan mean dan varians fitur per kelas. VarianceFloor mencegah logaritma varians nol.",
     "FitGaussian", "BAYDEMO menggunakan klasifikasi numerik sintetis dan mengamati posterior tiap kelas.",
     ["Load data berlabel TargetClass.",
      "Pilih VarianceFloor yang valid dan fit model.",
      "Prediksi sampel; baca label dan Probabilities untuk label 0..9.",
      "Periksa bahwa posterior berjumlah kira-kira satu dan kelas tak teramati bernilai nol."],
     "Probabilitas model bukan jaminan kalibrasi; asumsi independensi fitur adalah penyederhanaan."),
    ("TEXTDEMO", "Teks, token, dan TF-IDF", "AITEXT + AIBAYES + AISTATS + AIMODEL",
     "Pipeline teks ASCII kecil mengubah TSV menjadi token, vocabulary terpilih, vektor, lalu klasifikasi multinomial. Fit vocabulary hanya pada corpus train.",
     "FitText", "TEXTDEMO memakai TEXTTRN.TSV/TEXTEST.TSV dan Naive Bayes multinomial.",
     ["Periksa format TSV: label digit, TAB, kemudian teks ASCII.",
      "Load corpus dan fit vocabulary dengan batas feature yang didukung.",
      "Vectorize train/test memakai vocabulary train dan aturan IDF yang sama.",
      "FitMultinomial lalu prediksi; amati kata baru yang diabaikan."],
     "Tidak ada Unicode, stemming, stopword, n-gram atau embedding; fitur dan vocabulary sengaja kecil."),
    ("TREEDEMO", "Pohon keputusan", "AIDATA + AITREE + AIMODEL",
     "Pohon membagi fitur numerik memakai entropy dan information gain. Depth, MinLeaf, MinGain, serta batas 63 node membentuk kompleksitas.",
     "FitTree", "TREEDEMO memvisualisasikan prediksi/trace pada fixture kelas dengan batas kapasitas yang jelas.",
     ["Load data numerik berlabel.",
      "Pilih DepthLimit, MinLeaf, dan MinGain.",
      "FitTree lalu periksa status Truncated dan ukuran pohon.",
      "Gunakan TraceTree untuk melihat node dari akar hingga leaf."],
     "Tidak ada pruning, categorical split langsung, regression tree atau random forest."),
    ("RULEDEMO", "Sistem aturan dan forward chaining", "AIRULE + AIMODEL",
     "Aturan menurunkan fakta dalam putaran sampai tidak ada fakta baru. Provenance membantu menerangkan fakta hasil inferensi.",
     "Infer(", "RULEDEMO mendefinisikan fakta dan aturan, menjalankan Infer, lalu menampilkan trace.",
     ["Inisialisasi fakta dengan nama dan nilai yang konsisten.",
      "Tambahkan aturan setelah memeriksa premis dan kesimpulannya.",
      "Jalankan Infer dan baca urutan firing.",
      "Ubah fakta dasar; reset fakta turunan sebelum menjalankan ulang."],
     "Konflik aturan ditolak dan fakta tidak boleh ditimpa diam-diam."),
    ("PATHDEMO", "Pencarian jalur pada grid", "AISEARCH",
     "Grid kecil memperlihatkan BFS, DFS, dan A-star. Rute harus divalidasi terhadap dinding, batas grid, start dan goal.",
     "SearchGrid", "PATHDEMO membandingkan rute pada grid berhalang; A-star memakai heuristik grid.",
     ["Inisialisasi ukuran grid dan tambahkan dinding.",
      "Pastikan koordinat start dan goal berada dalam grid yang dapat dilalui.",
      "Jalankan BFS, DFS, atau A-star.",
      "Bandingkan panjang rute dan status Found; uji grid yang terputus."],
     "BFS menghasilkan rute terpendek pada biaya langkah seragam; DFS tidak menjamin rute terpendek."),
    ("FUZDEMO", "Inferensi fuzzy Mamdani", "AIFUZZY + AIPLOT",
     "Sistem fuzzy memetakan derajat keanggotaan input ke aturan dan centroid output. Nilai input harus berada pada universe yang dikonfigurasi.",
     "EvaluateFuzzy", "FUZDEMO memakai dua input, tiga himpunan dan aturan sederhana untuk menjelaskan defuzzifikasi.",
     ["Periksa rentang input/output dan parameter segitiga.",
      "Susun aturan dengan indeks himpunan yang valid.",
      "Evaluasi satu pasang input dan lihat kekuatan aturan.",
      "Bandingkan kasus low, tengah, high, lalu uji input di luar universe."],
     "Sistem menolak segmen degenerate dan evaluasi tanpa rule aktif."),
    ("QDEMO", "Q-learning pada dunia grid", "AIREWARD + AISEARCH + AIPLOT + AIMODEL",
     "Q-learning memilih aksi dari state dan menerima reward/penalti. Terminal state tidak melakukan bootstrap dari nilai Q berikutnya.",
     "TrainGridQ", "QDEMO melatih policy pada grid; hasilnya menekankan eksplorasi, epsilon decay, terminal reward, dan rute.",
     ["Bangun grid dengan start, goal dan dinding.",
      "Atur alpha, gamma, epsilon, penalti, serta seed.",
      "Jalankan training dan baca reward history serta policy greedy.",
      "Verifikasi rute tidak terjebak siklus dan mencapai terminal."],
     "Pelatihan dapat bergantung seed dan jumlah episode; periksa hasil, bukan hanya pesan training selesai."),
    ("OPTDEMO", "Optimizer dan satu langkah SGD", "AIOPTIM",
     "Optimizer menyediakan konfigurasi, validasi, clipping, momentum, dan early stopping yang dipakai model lanjutan.",
     "SGDStep", "OPTDEMO mengisolasi update parameter agar pengaruh rate, gradient clipping, dan momentum terlihat.",
     ["Panggil DefaultTraining untuk mengisi nilai valid.",
      "Catat value, velocity, gradient, rate dan momentum awal.",
      "Jalankan SGDStep/VectorStep dan hitung pembaruan secara manual.",
      "Uji konfigurasi invalid; pastikan fungsi gagal tanpa mutasi parsial."],
     "Clipping dilakukan per komponen dan L2 diterapkan oleh model, bukan SGDStep."),
    ("MODELIO", "Menyimpan dan memuat model", "AIMODEL",
     "AIMODEL menulis snapshot binary yang terikat ABI. Header, ukuran, endianness, layout dan checksum melindungi dari banyak berkas salah/rusak.",
     "SaveLinear", "MODELIO menunjukkan pasangan Save/Load dan pentingnya storage pemanggil untuk KNN.",
     ["Fit model valid sebelum menyimpan.",
      "Simpan ke path yang dapat ditulis; hindari mengandalkan file lama.",
      "Load ke variabel baru, validasi hasil, lalu bandingkan prediksi.",
      "Uji file rusak, truncated, trailing bytes, atau ABI berbeda."],
     "Format .TPM bukan format interchange; header lama TPAIMDL2 dipertahankan sebagai identitas format."),
    ("PLOTDEMO", "Grafik BGI dan SVG", "AIPLOT",
     "AIPLOT mengekspor SVG tanpa dependensi tambahan. Backend layar BGI hanya tersedia untuk build Turbo Pascal dengan GRAPH dan driver yang sesuai.",
     "SaveRegressionSVG", "PLOTDEMO membedakan data, rentang sumbu, label, dan alur ekspor SVG dari layar BGI.",
     ["Jalankan PLOTDEMO dengan working directory otp-AI.",
      "Pada Odin/FPC, pilih fungsi Save*SVG dan buka hasil di peramban.",
      "Periksa title, jumlah titik, label, dan rentang sumbu.",
      "Gunakan PlotOpen hanya pada build Turbo Pascal yang menyediakan GRAPH/BGI."],
     "Jika output SVG gagal ditulis, periksa AIError dan path; kegagalan tidak boleh dianggap sukses."),
]

CHAPTER_NOTES = {
    "BASIC": (
        "AIMATH menyediakan operasi numerik, vektor, jarak, dan matriks; AISTATS merangkum data menjadi statistik yang dapat dibaca model.",
        "Menghubungkan angka mentah, operasi aljabar, dan ringkasan statistik sebelum mempelajari estimator.",
        "N=2 untuk Euclidean/DotProduct; matriks A dan identitas B berukuran 2×2; statistik memakai lima nilai dan Variance(Sample=True).",
        "Jarak (1,2) ke (4,6)=5; dot product=16; sigmoid(0)=0.5; A×I=A; mean dan median=3; varians sampel=2.5; korelasi=1.",
        "Fondasi ML: jarak dipakai KNN/clustering, dot product membentuk skor model linear, statistik membantu memahami sebaran fitur.",
    ),
    "DATAPREP": (
        "AIDATA menangani CSV, missing value, imputer, scaler, kategori, dan encoding; AISPLIT membagi baris untuk train dan test.",
        "Membangun preprocessing berurutan pada data yang memiliki nilai hilang, lalu mengekspor hasil agar perubahan bisa diperiksa.",
        "TrainTestSplit fraction=0.25 membagi 25% untuk uji, shuffle=True mengacak, seed=42 mengulang urutan. FitImputer/FitScaler belajar dari train; ScaleStandard memakai mean dan SD.",
        "Program mencetak ringkasan dataset, jumlah baris terpilih, encoding MERAH/BIRU, dan menyimpan PREPTRN.CSV serta PREPTST.CSV.",
        "Mencegah data leakage: parameter imputasi dan scaling dihitung dari train saja, kemudian dipakai konsisten untuk test/produksi.",
    ),
    "REGDEMO": (
        "AISPLIT membentuk holdout; AILINEAR mempelajari koefisien regresi; AISTATS mengukur galat pada data uji.",
        "Menjalankan siklus supervised regression dari CSV sampai evaluasi, termasuk satu prediksi observasi baru dan grafik garis.",
        "TrainTestSplit(0.25, True, 42) berarti uji 25%, acak, seed tetap. FitLinear Ridge=0 berarti OLS tanpa penalti ridge; evaluasi memakai PredictLinearData(test); X baru=5.",
        "Mencetak jumlah train/test, intercept dan slope, MAE/RMSE, R2 jika terdefinisi, prediksi X=5, serta REGRESI.SVG.",
        "Memisahkan fit dari evaluasi membantu mengukur generalisasi; data jam/nilai bersifat sintetis dan tidak menunjukkan sebab-akibat.",
    ),
    "REGMULT": (
        "AILINEAR menyesuaikan satu model untuk satu atau banyak fitur; AISTATS menghitung metrik regresi dari target dan prediksi.",
        "Membaca efek beberapa fitur sekaligus dengan membandingkan koefisien hasil model terhadap persamaan sintetis yang diketahui.",
        "FitLinear(D, Ridge=0): Ridge=0 meminta OLS; dua kolom X menghasilkan dua koefisien. PredictLinearData membuat prediksi tiap baris; RegressionMetrics menghitung RMSE latih.",
        "Intercept diharapkan mendekati 5, koefisien fitur mendekati 2 dan -3, serta RMSE mendekati nol karena fixture dibuat dari persamaan itu.",
        "Mengenalkan representasi linear multivariat dan interpretasi bobot; kecocokan sempurna pada data pembangkit bukan bukti performa di luar sampel.",
    ),
    "KNNDEMO": (
        "AIKNN menyimpan dataset train dan mencari tetangga terdekat; AIDATA menskalakan fitur; AISTATS membuat confusion matrix dan skor.",
        "Melakukan klasifikasi tiga kelas dengan KNN dan melihat bagaimana skala fitur, nilai K, serta tetangga memengaruhi prediksi.",
        "Split 0.30/seed 42 menyisihkan 30% uji; ScaleStandard dipelajari pada train; K=3 berarti tiga tetangga; Classes=3 mengatur ukuran confusion matrix.",
        "Mencetak confusion matrix dan accuracy/macro-F1 uji, kemudian menulis KNN.SVG dengan warna berdasarkan label prediksi.",
        "Contoh supervised classification: K=3 menghaluskan keputusan lokal; scaling penting karena KNN mengandalkan jarak. BUNGA adalah data sintetis.",
    ),
    "KMEANS": (
        "AIKMEANS mengelompokkan baris berdasarkan pusat dan jarak; AIDATA menyediakan CSV dan scaling untuk membuat fitur sebanding.",
        "Menemukan tiga kelompok tanpa memakai target kelas, kemudian membaca pusat cluster, konvergensi, dan inertia.",
        "FitScaler(ScaleStandard); FitKMeans(K=3, MaxIter=100, Tolerance=0.0001, Seed=42): K jumlah cluster, MaxIter batas putaran, Tolerance batas pergeseran pusat, Seed pengacak awal.",
        "Mencetak status konvergensi, inertia, tiga pusat; menyimpan CLUSTER.SVG serta INERTIA.SVG.",
        "Memperkenalkan unsupervised learning: tidak ada label benar yang diberikan. Nomor cluster arbitrer; inertia bukan accuracy dan sensitif terhadap K/skala.",
    ),
    "CROSSVAL": (
        "AISPLIT menetapkan fold; AIKNN melatih/prediksi tiap fold; AIDATA melakukan scaling; AISTATS menghitung skor fold.",
        "Membandingkan evaluasi holdout dengan lima evaluasi bergilir sambil memastikan scaler selalu di-fit ulang di dalam fold train.",
        "MakeFolds(N, Folds=5, Shuffle=True, Seed=42) menentukan lima bagian acak yang dapat diulang; FoldSplit menahan satu bagian; KNN memakai K=3 tetangga.",
        "Satu accuracy dicetak per fold lalu accuracy gabungan; program juga menyatakan bahwa fold acak ini tidak stratified.",
        "Cross-validation memberi gambaran variasi akibat pemilihan sampel; preprocessing di dalam fold mencegah informasi test bocor ke train.",
    ),
    "LOGDEMO": (
        "AILINEAR berisi model logistik; AIOPTIM menyediakan konfigurasi training, clipping, momentum, dan stopping; AISTATS mengevaluasi klasifikasi.",
        "Melatih classifier biner yang memetakan fitur ke probabilitas kelas 1 dan menilai label setelah menerapkan threshold.",
        "Split 0.25/seed 42; ScaleStandard train-only; DefaultTraining mengisi rate/epoch/momentum; FitLogistic melatih; threshold=0.5 membagi probabilitas menjadi kelas 0/1.",
        "Mencetak epoch, loss akhir, stop reason, accuracy, confusion matrix, dan menyimpan LOGLOSS.SVG.",
        "Memperkenalkan sigmoid dan binary cross-entropy. Threshold mengubah trade-off keputusan, sementara metrik test mengukur hasil pada sampel terpisah.",
    ),
    "PERDEMO": (
        "AILINEAR menyatukan model linear; AIOPTIM mendukung pola optimisasi; Perceptron mengklasifikasi dengan aturan pembaruan berbasis salah klasifikasi.",
        "Membandingkan tugas AND yang dapat dipisahkan oleh garis dengan XOR yang tidak dapat dipisahkan oleh satu batas linear.",
        "FitPerceptron(MaxEpochs=100, Rate=0.1, Seed=42): batas epoch, besar langkah update, dan urutan acak. Dipanggil terpisah pada AND.CSV/XOR.CSV; score bukan probabilitas.",
        "AND diharapkan konvergen; XOR diharapkan tetap memiliki error dan tidak konvergen dengan perceptron tunggal.",
        "Contoh menunjukkan kapasitas hipotesis: kegagalan linear pada XOR menjadi motivasi memakai fitur non-linear atau jaringan multi-layer.",
    ),
    "NNDEMO": (
        "AINNET menjalankan neural network kecil; AIOPTIM memvalidasi aturan SGD, momentum, clipping, loss, dan early stopping.",
        "Belajar bagaimana hidden layer membuat XOR dapat dipelajari, membaca loss per epoch, lalu memeriksa penyimpanan model.",
        "FitNeural(Hidden=4); MaxEpochs=6000 adalah batas atas; Rate=0.5 ukuran langkah; Momentum=0.5 memakai velocity; Patience=1000; GoalLoss=0.01; seed default=42.",
        "Mencetak epoch/loss dan empat probabilitas/label prediksi; menulis XOR.TPM dan NNLOSS.SVG. Konvergensi tetap bergantung implementasi/seed.",
        "Menunjukkan representasi bertingkat dan gradient-based learning. Model edukatif 2-4-1, bukan neural network produksi.",
    ),
    "BAYDEMO": (
        "AIBAYES menghitung Gaussian Naive Bayes dan posterior kelas; AISPLIT membentuk holdout; AISTATS meringkas prediksi.",
        "Melatih distribusi fitur per kelas pada train dan mengubahnya menjadi prediksi serta probabilitas untuk sampel test.",
        "Split 0.30/seed 42; FitGaussian(VarianceFloor=0.000001) membatasi varians minimum; PredictBayes menghasilkan kelas/posterior; Classes=3 membangun confusion matrix.",
        "Mencetak confusion matrix dan Gaussian NB accuracy untuk test; probabilitas kelas disediakan ke setiap prediksi.",
        "Memperkenalkan probabilitas kondisional dan asumsi Naive Bayes bahwa fitur independen bersyarat pada kelas.",
    ),
    "TEXTDEMO": (
        "AITEXT mengubah teks menjadi token dan fitur bag-of-words/TF-IDF; AIBAYES melatih classifier multinomial; AISTATS menghitung hasil uji.",
        "Melatih vocabulary hanya dari corpus train, memvektorisasi teks, lalu mengklasifikasi pesan test tanpa memasukkan kata baru ke vocabulary.",
        "FitText Limit=8 membatasi fitur, MinDocumentFreq=1 menerima kata yang muncul minimal sekali, UseIDF=True memberi bobot IDF, Normalize=True memakai norm L2; Alpha=1 untuk smoothing.",
        "Mencetak kata vocabulary dan IDF, prediksi tiap teks beserta probabilitas, accuracy test, lalu menyimpan VOCAB.TPM dan TEXTNB.TPM.",
        "Memperkenalkan representasi teks menjadi vektor numerik dan mencegah leakage vocabulary. Cakupan terbatas pada teks ASCII dan vocabulary kecil.",
    ),
    "TREEDEMO": (
        "AITREE membangun pohon keputusan numerik; AIDATA membaca fixture; AIMODEL menyediakan simpan/muat snapshot pohon.",
        "Menelusuri keputusan split dari root ke leaf serta mengamati bagaimana gain nol memungkinkan pohon memecah XOR.",
        "FitTree(DepthLimit=4 membatasi level, MinLeaf=1 jumlah minimum leaf, MinGain=0 mengizinkan split gain nol); TraceTree mengembalikan node yang dilalui dan label.",
        "Mencetak jumlah node, prediksi untuk empat kombinasi XOR, dan setiap aturan threshold yang dilalui menuju leaf.",
        "Menghubungkan pemilihan split, entropy/information gain, kedalaman dan kompleksitas model dengan klasifikasi yang dapat diterangkan.",
    ),
    "RULEDEMO": (
        "AIRULE menyimpan fakta dan aturan serta menjalankan forward chaining; AIMODEL menyimpan rules/facts ke snapshot lokal.",
        "Menunjukkan inferensi simbolik: fakta internet dan listrik menghasilkan kesiapan perangkat, lalu kesiapan perangkat menghasilkan layanan kelas daring.",
        "AddFact memakai nilai 1=true dan -1=unknown; AddRule mendefinisikan indeks premis, nilai yang diharapkan, kesimpulan; Infer mengembalikan trace dan jumlah aturan aktif.",
        "Infer menyimpulkan perangkat siap dan kelas daring siap; RULES.TPM serta FACTS.TPM ditulis.",
        "Bukan model statistik: contoh membantu membedakan knowledge-based AI berbasis aturan dari supervised learning berbasis contoh berlabel.",
    ),
    "PATHDEMO": (
        "AISEARCH memodelkan grid, dinding, tetangga, dan algoritma BFS/DFS/A-star tanpa memakai dataset statistik.",
        "Membandingkan strategi eksplorasi untuk menemukan jalur dari start ke goal dalam grid kecil dengan dinding.",
        "InitGrid(6,6); SetWall pada kolom 3 kecuali baris 4; SearchGrid(start=1, goal=36, method=BFS..AStar).",
        "Mencetak found, cost, jumlah node expanded dan gambar grid untuk BFS, DFS, dan A-star.",
        "Mengajarkan pencarian state-space dan heuristic. Konsep ini berbeda dari belajar parameter model dari data.",
    ),
    "FUZDEMO": (
        "AIFUZZY mengelola fungsi keanggotaan segitiga, aturan Mamdani, firing strength dan centroid; AIPLOT menulis kurva hasil ke SVG.",
        "Menerjemahkan suhu/kelembapan linguistik ke keluaran kontinu kecepatan kipas, lalu memplot respons saat suhu berubah.",
        "DefaultFuzzy; EvaluateFuzzy suhu=28, kelembapan=70, resolusi centroid=200; sapuan suhu X=0..40 dengan kelembapan 70.",
        "Mencetak kecepatan kipas dan sembilan firing strength; menghasilkan FUZZY.SVG untuk kurva respons.",
        "Menunjukkan sistem aturan berbasis derajat keanggotaan yang dapat dibandingkan dengan klasifikasi/regresi yang belajar dari data.",
    ),
    "QDEMO": (
        "AIREWARD menyimpan Q-table dan memperbaruinya dari reward/transisi; AISEARCH menyediakan grid; AIPLOT merangkum return.",
        "Melatih agent melewati grid berhalang, kemudian memeriksa policy greedy apakah mencapai goal dan membentuk rute.",
        "Grid 4×4; InitQ(16 state, 4 aksi, alpha=0.3 laju update, gamma=0.95 diskonto, epsilon=0.25 eksplorasi); TrainGridQ(start=1, goal=16, episodes=1500, maxSteps=100, seed=42).",
        "Mencetak jumlah episode sukses/langkah, found/cost rute greedy, grid, QRETURN.SVG, QTABLE.TPM, dan GRID.TPM.",
        "Memperkenalkan reinforcement learning: agent belajar dari reward, eksplorasi epsilon, transisi, dan kondisi terminal—bukan label target per baris.",
    ),
    "OPTDEMO": (
        "AIOPTIM memvalidasi satu langkah SGD skalar/vektor dengan clipping dan momentum; model lain menggunakan prinsip serupa saat training.",
        "Mengisolasi pengaruh gradient, velocity, learning rate, dan momentum pada fungsi sederhana sebelum melihat optimizer tersembunyi di model.",
        "Mulai w=-5, v=0; objective (w-3)^2; gradient 2(w-3); SGDStep(rate=0.1 learning rate, momentum=0.3 bobot velocity, clip=10 batas gradient); 100 langkah.",
        "Setiap 10 langkah nilai w dan loss dicetak; loss seharusnya turun menuju minimum w=3.",
        "Membangun intuisi optimisasi numerik dan learning rate; parameter yang terlalu besar dapat mengganggu stabilitas update.",
    ),
    "MODELIO": (
        "AIMODEL memvalidasi dan menyimpan model; AILINEAR menyediakan regresi; AIKNN menunjukkan model yang terikat ke dataset storage.",
        "Membandingkan prediksi sebelum/sesudah save-load dan memahami bahwa snapshot binary hanya aman untuk ABI/compiler yang sama.",
        "FitLinear(Ridge=0); prediksi X=5; FitKNN(K=3); LoadKNN membutuhkan Storage pemanggil untuk membind dataset model.",
        "Prediksi linear dan KNN sebelum/sesudah load diharapkan sama; file LINEAR.TPM dan KNN.TPM dibuat.",
        "Model persistence menjaga parameter hasil training untuk pemakaian ulang; preprocessing, urutan fitur, dan ABI tetap bagian dari kontrak.",
    ),
    "PLOTDEMO": (
        "AIPLOT memvalidasi rentang data dan mengekspor scatter, kurva, serta garis regresi sebagai SVG; BGI hanya backend khusus compiler lama.",
        "Menghubungkan nilai x-y dengan visualisasi yang dapat diperiksa tanpa Python, layanan web, atau pustaka plotting tambahan.",
        "20 titik; x=i/2; y=10+3x+(i mod 3-1); SaveRegressionSVG dengan intercept=10, slope=3, dan judul.",
        "PLOT.SVG dihasilkan; Odin menampilkan pesan bahwa BGI khusus Turbo Pascal dan SVG dibuka di peramban.",
        "Visualisasi membantu memeriksa pola, residual, dan cluster; plot bukan pengganti validasi kuantitatif pada data uji.",
    ),
}


def load_font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), size)


def screenshot_image(number: int, title: str, filename: str, source: str) -> bytes:
    width, height = 1500, 790
    image = Image.new("RGB", (width, height), "#101827")
    draw = ImageDraw.Draw(image)
    mono = load_font(FONT_MONO, 22)
    small = load_font(FONT, 18)
    bold = load_font(FONT_BOLD, 19)
    draw.rounded_rectangle((18, 16, width - 18, height - 18), 24, fill="#101827", outline="#29374b", width=2)
    draw.rounded_rectangle((18, 16, width - 18, 76), 24, fill="#1b283a")
    draw.rectangle((18, 53, width - 18, 76), fill="#1b283a")
    for x, color in ((48, "#fb7185"), (78, "#fbbf24"), (108, "#34d399")):
        draw.ellipse((x, 39, x + 16, 55), fill=color)
    draw.text((150, 32), f"EXAMPLES/{filename}", font=bold, fill="#e2e8f0")
    draw.rounded_rectangle((width - 384, 27, width - 42, 65), 14, fill="#0f766e")
    draw.text((width - 360, 35), f"CAPTURE {number:02d}  |  LANGKAH 02", font=small, fill="white")
    draw.rectangle((18, 78, 195, height - 20), fill="#152237")
    labels = ["01  EXAMPLES", "02  SOURCE", "03  UNITS", "04  DATA"]
    for i, label in enumerate(labels):
        y = 112 + i * 48
        color = "#6ee7d8" if i == 1 else "#94a3b8"
        draw.text((38, y), label, font=small, fill=color)
    draw.rectangle((196, 78, width - 20, height - 20), fill="#0b1220")
    draw.text((230, 98), title, font=bold, fill="#8be9fd")
    draw.line((220, 136, width - 40, 136), fill="#253449", width=2)

    lines = source.splitlines()[:20]
    y = 160
    for index, line in enumerate(lines, 1):
        display = line.rstrip()
        if len(display) > 111:
            display = display[:108] + "..."
        draw.text((232, y), f"{index:02d}", font=mono, fill="#64748b")
        color = "#e2e8f0"
        stripped = display.strip()
        if stripped.startswith(("uses ", "program ", "function ", "procedure ", "begin", "end")):
            color = "#93c5fd"
        if stripped.startswith("{") or stripped.startswith("//"):
            color = "#86efac"
        draw.text((286, y), display, font=mono, fill=color)
        y += 28
    draw.rounded_rectangle((226, height - 92, width - 42, height - 42), 12, fill="#14283a", outline="#1c6570", width=2)
    draw.text((248, height - 81), "KODE DITARIK DARI SOURCE PAKET SAAT PDF DIBANGUN", font=small, fill="#99f6e4")
    draw.text((248, height - 55), "Ilustrasi editor untuk tutorial; susunan menu dapat berbeda antarversi.", font=small, fill="#94a3b8")
    stream = io.BytesIO()
    image.save(stream, format="PNG", optimize=True)
    return stream.getvalue()


def cover_image() -> bytes:
    w, h = 1800, 2546
    image = Image.new("RGB", (w, h))
    pix = image.load()
    for y in range(h):
        t = y / h
        c1 = (6, 18, 44)
        c2 = (9, 75, 86)
        c3 = (12, 31, 66)
        for x in range(w):
            u = x / w
            target = c2 if u > 0.55 else c1
            blend = 0.35 * t + 0.18 * u
            pix[x, y] = tuple(int(c1[i] * (1 - blend) + target[i] * blend) for i in range(3))
    draw = ImageDraw.Draw(image, "RGBA")
    for i in range(12):
        x = 960 + (i % 4) * 185
        y = 340 + (i // 4) * 185
        for j in range(3):
            x2 = x + 110 + j * 75
            y2 = y + (j - 1) * 80
            draw.line((x, y, x2, y2), fill=(48, 222, 204, 90), width=5)
            draw.ellipse((x2 - 11, y2 - 11, x2 + 11, y2 + 11), fill=(92, 234, 211, 220))
        draw.ellipse((x - 27, y - 27, x + 27, y + 27), fill=(255, 181, 84, 240))
    title_font = load_font(FONT_BOLD, 120)
    subtitle_font = load_font(FONT, 49)
    author_font = load_font(FONT_BOLD, 42)
    label_font = load_font(FONT_BOLD, 25)
    draw.rounded_rectangle((115, 180, 610, 245), 28, fill=(11, 211, 192, 220))
    draw.text((145, 195), "BUKU TUTORIAL  |  EDISI 2.0", font=label_font, fill="#07152f")
    draw.text((118, 340), "OTP-AI", font=title_font, fill="#ffffff", stroke_width=1)
    draw.text((125, 505), "MACHINE LEARNING", font=subtitle_font, fill="#c9fff6")
    draw.text((125, 574), "DENGAN PASCAL", font=subtitle_font, fill="#c9fff6")
    draw.line((125, 690, 900, 690), fill=(255, 181, 84, 210), width=5)
    draw.text((125, 735), "Panduan tutorial 20 program contoh", font=subtitle_font, fill="#ffffff")
    draw.text((125, 812), "untuk Odin Turbo Pascal", font=subtitle_font, fill="#ffffff")
    draw.rounded_rectangle((125, 1930, 1000, 2190), 32, fill=(7, 19, 43, 220), outline=(75, 219, 204, 150), width=3)
    draw.text((170, 1990), "Penulis", font=label_font, fill="#9ff6e7")
    draw.text((170, 2040), "Syams Ideris", font=author_font, fill="#ffffff")
    draw.text((170, 2103), "GNU GPL versi 3.0 atau yang lebih baru", font=label_font, fill="#c7d2fe")
    draw.text((125, 2360), "19 UNIT  •  20 CONTOH  •  LANGKAH PRAKTIS", font=label_font, fill="#9ff6e7")
    stream = io.BytesIO()
    image.save(stream, format="PNG", optimize=True)
    return stream.getvalue()


class Book:
    def __init__(self) -> None:
        self.doc = fitz.open()
        self.page = None
        self.y = 100
        self.section = "OTP-AI"
        self.toc_entries: list[tuple[str, int, int]] = []

    def new_page(self, section: str, title: str, subtitle: str = ""):
        self.page = self.doc.new_page(width=PAGE_W, height=PAGE_H)
        self.page.draw_rect(self.page.rect, color=PAPER, fill=PAPER)
        self.page.draw_rect(fitz.Rect(0, 0, PAGE_W, 8), color=TEAL, fill=TEAL)
        self.section = section
        self.page.insert_text((44, 43), section.upper(), fontsize=8.5, fontname="otp-bold", fontfile=str(FONT_BOLD), color=TEAL)
        self.page.insert_text((44, 79), title, fontsize=23, fontname="otp-bold", fontfile=str(FONT_BOLD), color=NAVY)
        self.y = 105
        if subtitle:
            self.paragraph(subtitle, size=10, color=MUTED, gap=10)
        return self.page

    def add_footer(self) -> None:
        for i, page in enumerate(self.doc):
            if i == 0:
                continue
            page.draw_line((44, 806), (PAGE_W - 44, 806), color=(0.82, 0.86, 0.88), width=0.6)
            page.insert_text((44, 824), "OTP-AI  •  Syams Ideris  •  GPL-3.0-or-later",
                             fontsize=7.4, fontname="otp", fontfile=str(FONT), color=MUTED)
            page.insert_text((PAGE_W - 68, 824), f"{i + 1:02d}",
                             fontsize=8, fontname="otp-bold", fontfile=str(FONT_BOLD), color=TEAL)

    def paragraph(self, value: str, size: float = 11, color=INK, gap: float = 8,
                  x: float = 46, width: float = 500, bold: bool = False,
                  lineheight: float = 1.38) -> None:
        font_path = FONT_BOLD if bold else FONT
        font = fitz.Font(fontfile=str(font_path))
        max_width = width
        lines: list[str] = []
        for raw in value.splitlines() or [""]:
            if not raw:
                lines.append("")
                continue
            current = ""
            for word in raw.split():
                candidate = word if not current else current + " " + word
                if font.text_length(candidate, fontsize=size) <= max_width:
                    current = candidate
                else:
                    if current:
                        lines.append(current)
                    current = word
            if current:
                lines.append(current)
        leading = size * lineheight
        for line in lines:
            if self.y + leading > 790:
                self.y = 790 - leading
            self.page.insert_text((x, self.y + size), line, fontsize=size,
                                  fontname="otp-bold" if bold else "otp",
                                  fontfile=str(font_path), color=color)
            self.y += leading
        self.y += gap

    def bullet(self, value: str, color=INK, size: float = 10.2) -> None:
        self.page.draw_circle((56, self.y + 7), 3, color=TEAL, fill=TEAL)
        self.paragraph(value, size=size, x=69, width=470, gap=5)

    def info_block(self, title: str, body: str, tone=TEAL) -> None:
        start = self.y
        self.paragraph(title, size=9.2, color=tone, bold=True, gap=2, x=55, width=480)
        self.paragraph(body, size=8.7, color=INK, gap=5, x=55, width=480, lineheight=1.28)
        rect = fitz.Rect(43, start - 2, 552, self.y - 2)
        self.page.draw_rect(rect, color=(0.90, 0.94, 0.94), fill=(0.90, 0.94, 0.94), overlay=False)
        self.page.draw_rect(fitz.Rect(43, start - 2, 47, self.y - 2), color=tone, fill=tone)

    def callout(self, title: str, body: str, tone=TEAL) -> None:
        start = self.y
        self.paragraph(title, size=10, color=tone, bold=True, gap=3, x=58, width=480)
        self.paragraph(body, size=9.5, color=INK, gap=7, x=58, width=480)
        rect = fitz.Rect(43, start - 5, 552, self.y - 3)
        self.page.draw_rect(rect, color=PALE, fill=PALE, overlay=False)
        self.page.draw_rect(fitz.Rect(43, start - 5, 48, self.y - 3), color=tone, fill=tone)

    def image(self, data: bytes, rect: fitz.Rect) -> None:
        self.page.insert_image(rect, stream=data, keep_proportion=True)

    def screenshot(self, number: int, title: str, filename: str, source: str,
                   rect: fitz.Rect) -> None:
        self.image(screenshot_image(number, title, filename, source), rect)

    def save(self) -> None:
        self.add_footer()
        self.doc.set_metadata({
            "title": "OTP-AI — Machine Learning dengan Pascal",
            "author": "Syams Ideris",
            "subject": "Panduan tutorial unit AI untuk Odin Turbo Pascal",
            "keywords": "OTP-AI, Pascal, Odin Turbo Pascal, GPL-3.0-or-later, machine learning",
            "creator": "OTP-AI Book Builder",
            "producer": f"PyMuPDF {fitz.VersionBind}",
        })
        toc = [[1, "Kata Pengantar", 3], [1, "Cara Menggunakan Buku", 6]]
        toc.extend([ [1, f"{i:02d}. {item[0]} — {item[1]}", 7 + (i - 1) * 2]
                     for i, item in enumerate(TUTORIALS, 1)])
        toc.extend([[1, "Lampiran A — Peta 19 Unit", 47],
                    [1, "Lampiran B — Diagnostik dan batas", 48],
                    [1, "Lisensi GNU GPL versi 3.0 atau yang lebih baru", 49]])
        self.doc.set_toc(toc)
        self.doc.save(OUT, garbage=4, deflate=True)


def get_snippet(name: str, marker: str, lines: int = 15) -> str:
    path = ROOT / "EXAMPLES" / f"{name}.PAS"
    source = path.read_text(encoding="utf-8", errors="replace").splitlines()
    pos = next((i for i, line in enumerate(source) if marker.lower() in line.lower()), 6)
    start = max(0, pos - lines // 2)
    end = min(len(source), start + lines)
    start = max(0, end - lines)
    selected = source[start:end]
    while selected and not selected[0].strip():
        selected.pop(0)
    while selected and not selected[-1].strip():
        selected.pop()
    return "\n".join(selected)


def make_book() -> None:
    book = Book()

    # Full-color cover.
    page = book.doc.new_page(width=PAGE_W, height=PAGE_H)
    page.insert_image(page.rect, stream=cover_image(), keep_proportion=False)

    # Copyright and publication details.
    book.new_page("IDENTITAS BUKU", "Hak cipta dan lisensi")
    book.paragraph("OTP-AI — Machine Learning dengan Pascal", size=17, bold=True, color=NAVY, gap=12)
    book.paragraph("Penulis: Syams Ideris", size=12, bold=True, gap=5)
    book.paragraph("Hak cipta (c) 2026 Syams Ideris.", size=11, gap=5)
    book.paragraph("Buku ini dilisensikan berdasarkan GNU General Public License versi 3.0, atau (sesuai pilihan Anda) versi yang lebih baru (GPL-3.0-or-later). Teks lisensi lengkap disertakan pada bagian akhir buku dan di file LICENCE.TXT.", size=10.5, gap=12)
    book.callout("Pemberitahuan merek dan kompatibilitas",
                 "Odin Turbo Pascal adalah nama IDE/compiler pada proyek ini. Turbo Pascal 7.0 dan Free Pascal dibahas sebagai target/compiler terpisah; hasil pengujian satu compiler tidak otomatis membuktikan kompatibilitas compiler lain.")
    book.paragraph("Buku menggunakan source contoh dalam paket otp-AI. Gambar editor pada tutorial merupakan visualisasi layar yang dibuat dari source aktual; tata letak menu dapat berbeda menurut build IDE. Angka hasil hanya dicantumkan jika bersumber dari contoh atau laporan pengujian paket.", size=10, gap=10)
    book.paragraph("Edisi: OTP-AI 2.0.0. Untuk perubahan API, baca DOCS/API.TXT dan DOCS/DESIGN.TXT di dalam paket.", size=9, color=MUTED)

    # Foreword.
    book.new_page("PEMBUKA", "Kata pengantar")
    book.paragraph("Machine learning sering terasa jauh karena biasanya diperkenalkan lewat library besar, notebook, atau layanan daring. Buku ini memilih jalan yang berbeda: setiap langkah penting diperlihatkan dengan Pascal, data kecil, dan program yang dapat dibaca dari awal hingga akhir.", size=12, gap=11)
    book.paragraph("OTP-AI berisi 19 unit Pascal untuk matematika dan matriks, data, preprocessing, validasi, regresi, klasifikasi, neural network kecil, teks, pohon, aturan, pencarian, fuzzy, reinforcement learning, plotting, serta penyimpanan model. Dua puluh program contoh membawa pembaca dari operasi numerik dasar menuju model AI yang lebih kaya.", size=11.2, gap=10)
    book.paragraph("Tujuan buku bukan menjanjikan model siap produksi. Batas ukuran, asumsi algoritma, status kompilasi, dan hal yang belum diuji ditulis secara terbuka. Data contoh bersifat sintetis; ia baik untuk belajar dan buruk sebagai bukti mutu pada data nyata.", size=11.2, gap=10)
    book.paragraph("Ikuti latihan dengan mengubah satu parameter setiap kali. Baca kode sebelum menekan Run, catat prediksi Anda, lalu bandingkan hasil. Jika satu contoh gagal, periksa pesan error dan working directory sebelum mengubah model.", size=11.2, gap=15)
    book.paragraph("Selamat belajar dan bereksperimen.", size=12, bold=True, color=TEAL, gap=6)
    book.paragraph("Syams Ideris", size=11, color=NAVY, bold=True)

    # Contents pages.
    book.new_page("NAVIGASI", "Daftar isi", "Bab tutorial memakai source terkini dari folder EXAMPLES.")
    for i, item in enumerate(TUTORIALS[:10], 1):
        book.paragraph(f"{i:02d}  {item[0]} — {item[1]}     {7 + (i - 1) * 2}", size=10.2, gap=7)
    book.paragraph("Peta unit dan referensi", size=10.2, bold=True, color=TEAL, gap=6)
    book.paragraph("Lampiran A — Peta 19 unit                                      47", size=10, gap=5)
    book.paragraph("Lampiran B — Diagnostik dan batas                        48", size=10, gap=5)
    book.paragraph("GNU GPL versi 3.0 atau yang lebih baru             49+", size=10, gap=5)
    book.new_page("NAVIGASI", "Daftar isi · lanjutan")
    for i, item in enumerate(TUTORIALS[10:], 11):
        book.paragraph(f"{i:02d}  {item[0]} — {item[1]}     {7 + (i - 1) * 2}", size=10.2, gap=7)
    book.callout("Peta belajar",
                 "Ikuti urutan dari BASIC hingga PLOTDEMO. Jika fokus Anda satu topik, gunakan unit canonical di Lampiran A dan API.TXT untuk mencari signature resmi.")

    # Getting started.
    book.new_page("MULAI", "Cara menggunakan buku")
    book.paragraph("Siapkan compiler Odin Turbo Pascal dari proyek ini. Buka satu program .PAS, tambahkan folder otp-AI/UNITS ke Unit search paths dan otp-AI/EXAMPLES ke Include search paths. Jalankan program dengan working directory otp-AI agar berkas DATA dan OUTPUT dapat ditemukan.", size=10.8, gap=9)
    book.paragraph("Kompilasi dari terminal:", size=10.5, bold=True, color=TEAL, gap=5)
    book.callout("Perintah Odin",
                 "mkdir -p BIN && odinpc build EXAMPLES/BASIC.PAS --out BIN/BASIC --unit-path UNITS --include-path EXAMPLES --rtl /path/ke/Odin_Turbo_Pascal/rtl",
                 tone=AMBER)
    book.paragraph("Atau gunakan Free Pascal mode TP untuk memeriksa kompatibilitas source: sh BUILDFPC.SH. Build script mengompilasi contoh dan test, tetapi pada host ini eksekusi/link Free Pascal belum terverifikasi.", size=10, gap=8)
    book.paragraph("Struktur paket", size=10.5, bold=True, color=TEAL, gap=4)
    for item in ["UNITS — 19 unit Pascal canonical.", "EXAMPLES — 20 tutorial program dan COMMON.INC.",
                 "DATA — fixture CSV/TSV sintetis.", "TESTS — suite Pascal, oracle, dan pembanding numerik opsional.",
                 "DOCS — API, rancangan, panduan, instalasi, serta laporan pengujian."]:
        book.bullet(item)
    book.callout("Urutan aman", "Baca klausa uses dan data input, build, jalankan dari root paket, periksa AIError bila fungsi mengembalikan False, lalu ubah hanya satu parameter.")

    # Example tutorials: two pages per example, with step-numbered editor illustration.
    for number, item in enumerate(TUTORIALS, 1):
        name, title, units, overview, marker, code_note, steps, takeaway = item
        unit_role, sample_goal, parameters, expected, ml_value = CHAPTER_NOTES[name]
        example_path = ROOT / "EXAMPLES" / f"{name}.PAS"
        snippet = get_snippet(name, marker)
        start_page = len(book.doc) + 1
        book.toc_entries.append((name, start_page, start_page + 1))

        book.new_page(f"BAB {number:02d} · {name}", title, f"Program {name}.PAS  |  Unit: {units}")
        book.paragraph(overview, size=11, gap=10)
        book.info_block("PERAN UNIT", unit_role)
        book.info_block("TUJUAN CONTOH", sample_goal)
        book.info_block("FUNGSI DAN PARAMETER UTAMA", parameters, tone=AMBER)
        book.info_block("HASIL YANG DIHARAPKAN", expected)
        book.info_block("POSISI DALAM PEMBELAJARAN MACHINE LEARNING", ml_value, tone=NAVY)
        book.info_block("ALUR KODE DAN CATATAN", f"{code_note} {takeaway}", tone=MUTED)
        book.paragraph(f"Rujukan source: EXAMPLES/{name}.PAS. Cuplikan pada halaman berikut diambil dari file tersebut.", size=8.5, color=MUTED, gap=0)

        book.new_page(f"BAB {number:02d} · LANGKAH", f"Praktik {number:02d} — {name}")
        book.paragraph("Ikuti langkah satu per satu. Nomor di ilustrasi menunjukkan urutan interaksi; sesuaikan detail menu jika build IDE Anda berbeda.", size=9.8, gap=5)
        for i, step in enumerate(steps, 1):
            book.page.draw_circle((57, book.y + 9), 11, color=TEAL, fill=TEAL)
            book.page.insert_text((53.5, book.y + 12), str(i), fontsize=8, fontname="otp-bold", fontfile=str(FONT_BOLD), color=WHITE)
            book.paragraph(step, size=9.3, x=77, width=463, gap=5)
        img = screenshot_image(number, title, example_path.name, snippet)
        book.image(img, fitz.Rect(44, 431, 551, 696))
        book.page.insert_text((45, 713), f"Gambar {number:02d}.1 — Visualisasi editor dengan cuplikan source {example_path.name}.",
                              fontsize=8.2, fontname="otp", fontfile=str(FONT), color=MUTED)
        book.y = 721
        book.paragraph(f"Periksa hasil: {takeaway}", size=9.1, color=TEAL, gap=5)
        book.paragraph("Catatan: source pada gambar diambil langsung dari file saat PDF dibangun. Screenshot editor dibuat sebagai ilustrasi, bukan bukti tampilan atau menu tertentu.", size=8.2, color=MUTED, gap=0)

    # Unit map.
    book.new_page("LAMPIRAN A", "Peta 19 unit canonical", "Nama berikut cocok dengan file yang ada pada otp-AI/UNITS.")
    units = [
        ("AITYPES", "Tipe bersama, batas, dan error."),
        ("AIMATH", "Numerik, jarak, random, dan matriks."),
        ("AISTATS", "Statistik dan metrik evaluasi."),
        ("AIDATA", "CSV, imputer, scaler, kategori, one-hot."),
        ("AISPLIT", "Train/test split dan K-fold."),
        ("AILINEAR", "Regresi linear/logistik dan perceptron."),
        ("AIKNN", "K-nearest neighbors."),
        ("AIKMEANS", "Clustering K-means."),
        ("AIOPTIM", "SGD, momentum, clipping, stopping."),
        ("AINNET", "Jaringan saraf kecil."),
        ("AIBAYES", "Gaussian dan multinomial Naive Bayes."),
        ("AITREE", "Pohon klasifikasi numerik."),
        ("AITEXT", "Tokenisasi, corpus, dan TF-IDF."),
        ("AIRULE", "Fakta, aturan, forward chaining."),
        ("AISEARCH", "Grid search BFS/DFS/A-star."),
        ("AIFUZZY", "Fuzzy Mamdani."),
        ("AIREWARD", "Q-learning."),
        ("AIMODEL", "Save/Load snapshot model."),
        ("AIPLOT", "SVG dan backend grafik bersyarat."),
    ]
    for unit, desc in units:
        book.paragraph(unit, size=9.6, color=TEAL, bold=True, gap=1)
        book.paragraph(desc, size=9, x=145, width=390, gap=4)
    book.callout("Nama lama",
                 "Pada source sebelum konsolidasi, AIMATRIX→AIMATH, AIPREP→AIDATA, AIMETRIC→AISTATS, serta AIREG/AILOGREG/AIPERCEP→AILINEAR. Jangan menambahkan nama lama itu ke klausa uses contoh baru.")

    # Diagnostics.
    book.new_page("LAMPIRAN B", "Diagnostik, batas, dan kebiasaan baik")
    for title, body in [
        ("Pesan error", "Periksa nilai Boolean fungsi sebelum membaca output. Bila False, baca AIErrorCode dan AIError segera; panggilan berikut dapat mengganti status."),
        ("Dataset dan alokasi", "Alokasikan TDataSet dengan NewData/FreeData. Dataset besar jangan diletakkan sebagai local stack variable. Hindari membebaskan storage KNN sebelum model tidak lagi digunakan."),
        ("Kapasitas", "Dataset: 200 baris × 8 fitur; matriks: 16×16; model lain memiliki batas masing-masing. Batas bukan rekomendasi ukuran production."),
        ("Numerik", "Input publik dibatasi 1E12. Operasi matriks add/subtract/scale/multiply menolak hasil di luar batas, mengembalikan ErrValue, dan tidak memutasi output."),
        ("SVG dan BGI", "Pada Odin, ekspor SVG adalah jalur yang didukung. BGI bergantung pada Turbo Pascal, GRAPH.TPU, serta driver yang sesuai."),
        ("File .TPM", "Snapshot binary terikat compiler, ABI, ukuran tipe, endianness, dan layout. Jangan memindahkannya lintas compiler."),
        ("Pengujian", "Status terverifikasi di paket: Odin 2.5.0 berhasil compile 20 contoh, TESTALL 139 assertion, TESTADV 148 assertion. Turbo Pascal 7.0 asli dan BGI DOS belum diuji."),
    ]:
        book.paragraph(title, size=10, color=TEAL, bold=True, gap=2)
        book.paragraph(body, size=9.5, gap=7)
    book.callout("Bukan janji kinerja", "Contoh dan fixture bersifat sintetis. Validasi keputusan model pada data dan lingkungan yang relevan; buku ini tidak mengklaim akurasi produksi.")

    # Full GPL license appendix, from package copy of the official text.
    license_lines = (ROOT / "LICENCE.TXT").read_text(encoding="utf-8", errors="replace").splitlines()
    per_page = 60
    for start in range(0, len(license_lines), per_page):
        part = license_lines[start:start + per_page]
        page_no = len(book.doc) + 1
        title = "GNU GENERAL PUBLIC LICENSE · VERSI 3" if start == 0 else "GNU GPL VERSI 3 · LANJUTAN"
        book.new_page("LISENSI BUKU · GPL-3.0-OR-LATER", title)
        if start == 0:
            book.paragraph("OTP-AI — Copyright (c) 2026 Syams Ideris. Buku ini dilisensikan berdasarkan GPL versi 3.0 atau yang lebih baru.", size=8.5, color=TEAL, gap=5)
        text = "\n".join(part)
        font_size = 7.2
        while True:
            font = fitz.Font(fontfile=str(FONT))
            wrapped: list[str] = []
            for raw in text.splitlines():
                if not raw:
                    wrapped.append("")
                    continue
                current = ""
                for word in raw.split():
                    candidate = word if not current else current + " " + word
                    if font.text_length(candidate, fontsize=font_size) <= 500:
                        current = candidate
                    else:
                        if current:
                            wrapped.append(current)
                        current = word
                if current:
                    wrapped.append(current)
            leading = font_size * 1.25
            if len(wrapped) * leading < 685:
                break
            font_size -= 0.2
        spare = book.page.insert_textbox(fitz.Rect(46, book.y, 548, 790), "\n".join(wrapped),
                                         fontsize=font_size, fontname="otp", fontfile=str(FONT),
                                         color=INK, lineheight=1.25)
        if spare < 0:
            raise ValueError(f"GPL text does not fit on PDF page {page_no}")

    book.save()


if __name__ == "__main__":
    make_book()
