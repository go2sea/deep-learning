
#include "utils.cuh"

using namespace std;

void printTime(clock_t &t, string s){ 
	t = clock() - t;
	cout << "\n"<< s << ": " << ((float)t/CLOCKS_PER_SEC) << " s.";
	t = clock();
}

void initW(Matrix<float>* nvMat){
	int length = nvMat->getNumRows() * nvMat->getNumCols();
	float* a = new float[length];
	srand((unsigned)time(NULL));
	float bound = sqrt(1.0 / length);
	for(int i = 0; i < length; i++){
		int k = rand() % 200;
		if(k < 100)
			a[i] = (k/100.0)*(-bound);
		else
			a[i] = ((k - 100)/100.0)*bound; 
	}   
	nvMat->copyFromHost(a, length);
	delete a;
}

void gaussRand(Matrix<float>* nvMat, float var, float mean){
	int length = nvMat->getNumRows() * nvMat->getNumCols();
	float* a = new float[length];
	// std::default_random_engine generator;
	//  std::normal_distribution<float> distribution(mean, var);

	for(int i = 0; i < length; i++){
		//        float k = distribution(generator);
		if(var == 0)
			a[i] = 0.0f;
		else
			a[i] = gaussGen(var, mean); 
	} 
	nvMat->copyFromHost(a, length);
	delete a;
}

void gaussRand(float *w, int length, float var, float mean){
	// std::default_random_engine generator;
	//  std::normal_distribution<float> distribution(mean, var);

	for(int i = 0; i < length; i++){
		//        float k = distribution(generator);
		if(var == 0)
			w[i] = 0.0f;
		else
			w[i] = gaussGen(var, mean); 
	} 
}

float gaussGen(float var, float mean)
{
	static float V1, V2, S;
	static int phase = 0;
	float X;

	if ( phase == 0 ) {
		do {
			float U1 = (float)rand() / RAND_MAX;
			float U2 = (float)rand() / RAND_MAX;

			V1 = 2 * U1 - 1;
			V2 = 2 * U2 - 1;
			S = V1 * V1 + V2 * V2;
		} while(S >= 1 || S == 0);

		X = V1 * sqrt(-2 * log(S) / S);
	} else
		X = V2 * sqrt(-2 * log(S) / S);

	phase = 1 - phase;

	return (X * var + mean);
}

void readData(Matrix<float>* nvData, string filename, \
			bool isData, int addZerosInFront){
	int length = nvData->getNumRows() * nvData->getNumCols();
	ifstream fin(filename.c_str(), ios::binary);
	float* data = new float[length];
	char* readData = new char[length];
	fin.read(readData + addZerosInFront, length - addZerosInFront);
	for(int i = 0; i < length; i++){
		if(i < addZerosInFront)
			readData[i] = 0;
		unsigned char tmp = readData[i];
		if(isData){
			data[i] = (int)tmp / 255.0;
		}
		else
			data[i] = (int)tmp;
	}
	nvData->copyFromHost(data, length);
	fin.close();
	delete data;
	delete readData;
}

