import os 
dir_path = os.path.dirname(os.path.realpath(__file__))
data_path=os.path.join(dir_path, "data")

SAMPLE_NUMBER=1
file1 = open(os.path.join(data_path,f'whisper_{SAMPLE_NUMBER}.txt'), 'r', encoding='utf-8')
l1 = file1.readlines()
# Using readlines()
file2 = open(os.path.join(data_path,f'sample_{SAMPLE_NUMBER}.txt'), 'r', encoding='utf-8')
l2 = file2.readlines()

n=min(len(l1),len(l2))
print(f'n: {n}',l2)

for i in range(n):
    c1=l1[i]
    c2=l2[i]
    cur_len=min(len(l1[i]),len(l2[i]))
    # print(f'checking line {i}')
    if c1!=c2:
        print(f'string mismatch whisper:{c1}, file:{c2}')