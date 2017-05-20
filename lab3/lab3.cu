#include "lab3.h"
#include <cstdio>

__device__ __host__ int CeilDiv(int a, int b) { return (a-1)/b + 1; }
__device__ __host__ int CeilAlign(int a, int b) { return CeilDiv(a, b) * b; }

__global__ void SimpleClone(
	const float *background,
	const float *target,
	const float *mask,
	float *output,
	const int wb, const int hb, const int wt, const int ht,
	const int oy, const int ox
)
{
	const int yt = blockIdx.y * blockDim.y + threadIdx.y;
	const int xt = blockIdx.x * blockDim.x + threadIdx.x;
	const int curt = wt*yt+xt;
	if (yt < ht and xt < wt and mask[curt] > 127.0f) {
		const int yb = oy+yt, xb = ox+xt;
		const int curb = wb*yb+xb;
		if (0 <= yb and yb < hb and 0 <= xb and xb < wb) {
			output[curb*3+0] = target[curt*3+0];
			output[curb*3+1] = target[curt*3+1];
			output[curb*3+2] = target[curt*3+2];
		}
	}
}

__global__ void Jacobi(
	const float *background,
	const float *target,
	const float *mask,
	const float *output,
	float* next,
	const int wb, const int hb, const int wt, const int ht,
	const int oy, const int ox
)
{
	const int yt = blockIdx.y * blockDim.y + threadIdx.y;
	const int xt = blockIdx.x * blockDim.x + threadIdx.x;
	const int curt = wt*yt+xt;
	
	const int max_t = wt*ht;
	const int max_b = wb*hb;
	if (yt < ht and xt < wt and mask[curt] > 127.0f) {
		const int yb = oy+yt, xb = ox+xt;
		const int curb = wb*yb+xb;
		if (0 <= yb and yb < hb and 0 <= xb and xb < wb) {
			// cb = 1/4(4*ct-(Nt +Wt +St +Et)+(Nb +Wb)+(Sb +Eb))
			const int nt = curt-wt;
			const int st = curt+wt;
			const int wt = curt-1;
			const int et = curt+1;

			const int nb = curb-wb;
			const int sb = curb+wb;
			const int wb = curb-1;
			const int eb = curb+1;

			const int tvs[] = {nt, st, wt, et};
			const int bvs[] = {nb, sb, wb, eb};

			int count = 0;
			float tmp[3] = {0, 0, 0};
			bool boundary = false;
			for(int i = 0; i < 4; ++i){
				const int tp = tvs[i];
				const int bp = bvs[i];
				if(mask[tp] < 127 || tp < 0 || tp >= max_t){
					boundary = true;
					break;
				}

				if(bp >= 0 && bp < max_b){
					for(int j = 0; j < 3; ++j){
						const float ctv = target[curt*3+j];
						const float tpv = target[tp*3+j];
						const float bpv = output[bp*3+j];
						
						tmp[j] += ctv - tpv + bpv;
					}
					++count;
				}
			}

			if (boundary){
				next[curb*3+0] = background[curb*3+0];
				next[curb*3+1] = background[curb*3+1];
				next[curb*3+2] = background[curb*3+2];
			}
			else if(count > 0){
				next[curb*3+0] = tmp[0] / count;
				next[curb*3+1] = tmp[1] / count;
				next[curb*3+2] = tmp[2] / count;
			}
		}
	}
}

void PoissonImageCloning(
	const float *background,
	const float *target,
	const float *mask,
	float *output,
	const int wb, const int hb, const int wt, const int ht,
	const int oy, const int ox
)
{
	cudaMemcpy(output, background, wb*hb*sizeof(float)*3, cudaMemcpyDeviceToDevice);
	SimpleClone<<<dim3(CeilDiv(wt,32), CeilDiv(ht,16)), dim3(32,16)>>>(
		background, target, mask, output,
		wb, hb, wt, ht, oy, ox
	);

	float* next;
	cudaMalloc(&next, 3*wb*hb*sizeof(float));

	for(int i = 0; i < 10000; ++i){
		Jacobi<<<dim3(CeilDiv(wt,32), CeilDiv(ht,16)), dim3(32,16)>>>(
			background, target, mask, output, next,
			wb, hb, wt, ht, oy, ox
		);

		Jacobi<<<dim3(CeilDiv(wt,32), CeilDiv(ht,16)), dim3(32,16)>>>(
			background, target, mask, next, output,
			wb, hb, wt, ht, oy, ox
		);
	}

	cudaFree(next);
}
