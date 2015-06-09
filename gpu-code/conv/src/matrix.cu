///
/// \file Matrix<Dtype>.cuh
/// \brief 矩阵类源文件

#include <cuda_runtime.h>
#include <stdlib.h>
#include <stdio.h>

#include "Matrix<Dtype>.cuh"

using namespace std;

template <typename Dtype>
Matrix<Dtype>::Matrix(int num_row, int num_col){
	_init(num_row, num_col);
}

template <typename Dtype>
Matrix<Dtype>::Matrix(const Matrix<Dtype>* like, bool copy){
	_init(like->getNumRows(), like->getNumCols());
	if (copy) {
		copyFromDevice(like);
	}
}

template <typename Dtype>
Matrix<Dtype>::Matrix(const Matrix<Dtype>* like) {
	_init(like->getNumRows(), like->getNumCols());
}

template <typename Dtype>
Matrix<Dtype>::Matrix(Dtype* dev_data, int num_row, int num_col) {
	_shape[0] = num_row;
	_shape[1] = num_col;
	_amount = num_row * num_col;
	_is_own_data = false;
	_data_value = dev_data;				
}

template <typename Dtype>
Matrix<Dtype>::~Matrix(){
	if(_is_own_data && _amount > 0){
		cudaFree(_data_value);
	}
	if(_is_own_diff && _amount > 0){
		cudaFree(_data_value);
	}
}

template <typename Dtype>
void Matrix<Dtype>::_init(int num_row, int num_col) {
	_shape[0] = num_row;
	_shape[1] = num_col;
	_amount = num_row * num_col;
	_is_own_data = true;
	_is_own_diff = false;	
	if (_amount > 0) {
		cudaError_t status;
		status = cudaMalloc((void**) &_data_value, \
				_shape[0] * _shape[1] * sizeof(Dtype));
		/*
		else if(a == ALLOC_ON_UNIFIED_MEMORY){
			status = cudaMallocManaged(&_data_value, \
				_shape[0] * _shape[1] * sizeof(Dtype));
		}*/
		if (status != cudaSuccess) {
			fprintf(stderr, "!!!! device memory allocation error\n");
			exit(EXIT_FAILURE);
		}
	} 
}

template <typename Dtype>
void Matrix<Dtype>::getTranspose(Matrix<Dtype>* target){
	
	const int width = _shape[1];
	const int height = _shape[0];
	const int num_blocks_x = DIVUP(width, ADD_BLOCK_SIZE);
	assert(num_blocks_x < NUM_BLOCKS_MAX);
	const int num_blocks_y = max(1, min(DIVUP(height, ADD_BLOCK_SIZE), \
				NUM_BLOCKS_MAX));
	dim3 grid_size(num_blocks_x, num_blocks_y, 1); 
	dim3 block_size(ADD_BLOCK_SIZE, ADD_BLOCK_SIZE, 1); 
	
	kTranspose<<<grid_size, block_size>>>(_data_value, \
				target->getDevData(), width, height);
	cudaThreadSynchronize();
}

template <typename Dtype>
void Matrix<Dtype>::rightMult(Matrix<Dtype>* b, float scale_AB, \
		Matrix<Dtype> *target, cublasHandle_t& handle) {

	clock_t t = clock();

	int m = this->_shape[0];
	int k = this->_shape[1];
	int n = b->getNumCols();
	float scale_tar = 0;
	assert(k == b->getNumRows());
	//列主
	cublasSgemm(handle, CUBLAS_OP_N, CUBLAS_OP_N, n, m, k, &scale_AB, \
				b->getDevData(), n, this->getDevData(), k, \
				&scale_tar, target->getDevData(), n);
}

template <typename Dtype>
void Matrix<Dtype>::addColVector(Matrix<Dtype>* vec){
	addColVector(vec, 1, this);
}

template <typename Dtype>
void Matrix<Dtype>::addColVector(Matrix<Dtype>* vec, float scaleVec, Matrix<Dtype>* target){

	Matrix<Dtype>* ori_trans = new Matrix(_shape[1], _shape[0]);
	this->getTranspose(ori_trans);
	ori_trans->addRowVector(vec);
	ori_trans->getTranspose(target);
	delete ori_trans;
}

template <typename Dtype>
void Matrix<Dtype>::addRowVector(Matrix<Dtype>* vec){
	addRowVector(vec, 1, this);	
}

template <typename Dtype>
void Matrix<Dtype>::addRowVector(Matrix<Dtype>* vec, float scaleVec, Matrix<Dtype>* target){
	assert(vec->getNumRows() == 1 || vec->getNumCols() == 1);
	assert(vec->getNumRows() == _shape[0] || vec->getNumCols() == _shape[1]);
	const int width = _shape[1];
	const int height = _shape[0];

	//表达成了矩阵的结构，就分开处理算了,block和thread的x维控制列数
	const int num_blocks_x = DIVUP(width, ADD_BLOCK_SIZE);
	assert(num_blocks_x < NUM_BLOCKS_MAX);
	const int num_blocks_y = max(1, min(DIVUP(height, ADD_BLOCK_SIZE), \
				NUM_BLOCKS_MAX));
	dim3 grid_size(num_blocks_x, num_blocks_y, 1); 
	dim3 block_size(ADD_BLOCK_SIZE, ADD_BLOCK_SIZE, 1); 

	kAddRowVector<<<grid_size, block_size>>>(_data_value, vec->getDevData(), \
			target->getDevData(), width, height, scaleVec);
	cudaThreadSynchronize();
	
}

template <typename Dtype>
void Matrix<Dtype>::subtractFromScalar(float scalar, Matrix<Dtype>* target) { 

	const int width = _shape[1];
	const int height = _shape[0];
	const int num_blocks_x = DIVUP(width, ADD_BLOCK_SIZE);
	assert(num_blocks_x < NUM_BLOCKS_MAX);
	const int num_blocks_y = max(1, min(DIVUP(height, ADD_BLOCK_SIZE), \
				NUM_BLOCKS_MAX));
	dim3 grid_size(num_blocks_x, num_blocks_y, 1); 
	dim3 block_size(ADD_BLOCK_SIZE, ADD_BLOCK_SIZE, 1); 
	
	kSubtractFromScalar<<<grid_size, block_size>>>(_data_value, scalar, \
			target->getDevData(), width, height);
	cudaThreadSynchronize();
}

template <typename Dtype>
void Matrix<Dtype>::subtractFromScalar(float scalar) {
	subtractFromScalar(scalar, this);
}

template <typename Dtype>
void Matrix<Dtype>::apply(Matrix<Dtype>::FUNCTIONS f, Matrix<Dtype> *target){
	
	const int width = _shape[1];
	const int height = _shape[0];
	const int num_blocks_x = DIVUP(width, ADD_BLOCK_SIZE);
	assert(num_blocks_x < NUM_BLOCKS_MAX);
	const int num_blocks_y = max(1, min(DIVUP(height, ADD_BLOCK_SIZE), \
				NUM_BLOCKS_MAX));
	dim3 grid_size(num_blocks_x, num_blocks_y, 1); 
	dim3 block_size(ADD_BLOCK_SIZE, ADD_BLOCK_SIZE, 1); 

	if(f == Matrix<Dtype>::SOFTMAX){
		//一个block只计算一行数据
		grid_size = dim3(1, height, 1);
		block_size = dim3(num_blocks_x * ADD_BLOCK_SIZE, 1, 1);
		kSoftmax<<<grid_size, block_size, sizeof(Dtype) * width>>>(_data_value, \
				_shape[1], _shape[0]);
	}else if(f == Matrix<Dtype>::RECIPROCAL) {
		kReciprocal<<<grid_size, block_size>>>(_data_value, target->getDevData(), \
				width, height);
	}else if(f == Matrix<Dtype>::LOG) {
		kLog<<<grid_size, block_size>>>(_data_value, target->getDevData(), \
				width, height);
	}else if(f == Matrix<Dtype>::SIGMOID) {
		kSigmoid<<<grid_size, block_size>>>(_data_value, target->getDevData(), \
				width, height);
	}
	cudaThreadSynchronize();
}

template <typename Dtype>
void Matrix<Dtype>::apply(Matrix<Dtype>::FUNCTIONS f) {
	apply(f, this);
}

template <typename Dtype>
void Matrix<Dtype>::sumCol(Matrix<Dtype>* target){
	const int width = _shape[1];
	const int height = _shape[0];
	const int num_blocks_x = DIVUP(width, ADD_BLOCK_SIZE);
	assert(num_blocks_x < NUM_BLOCKS_MAX);
	dim3 grid_size(1, height, 1); 
	dim3 block_size(num_blocks_x * ADD_BLOCK_SIZE, 1, 1); 
	
	kDumbSumCols<<<grid_size, block_size, sizeof(Dtype) * width>>>(_data_value, \
			target->getDevData(), width, height);
	cudaThreadSynchronize();
}

template <typename Dtype>
void Matrix<Dtype>::sumRow(Matrix<Dtype>* target){
	Matrix<Dtype>* trans = new Matrix(_shape[1], _shape[0]);
	this->getTranspose(trans);
	trans->sumCol(target);
	delete trans;
}

//位置下标从0开始
template <typename Dtype>
void Matrix<Dtype>::maxPosInRow(Matrix<Dtype>* maxVec){
	const int width = _shape[1];
	const int height = _shape[0];
	const int num_blocks_x = DIVUP(width, ADD_BLOCK_SIZE);
	assert(num_blocks_x < NUM_BLOCKS_MAX);
	dim3 grid_size(1, height, 1); 
	dim3 block_size(num_blocks_x * ADD_BLOCK_SIZE, 1, 1); 
	
	kDumbMaxPosInRow<<<grid_size, block_size, sizeof(Dtype) * width>>>(_data_value, \
			maxVec->getDevData(), width, height);
	cudaThreadSynchronize();
}

template <typename Dtype>
void Matrix<Dtype>::eltWiseMult(Matrix<Dtype>* b, Matrix<Dtype>* target) {

	assert(b->getNumCols() == _shape[1]);

	const int width = _shape[1];
	const int height = _shape[0];
	const int num_blocks_x = DIVUP(width, ADD_BLOCK_SIZE);
	assert(num_blocks_x < NUM_BLOCKS_MAX);
	const int num_blocks_y = max(1, min(DIVUP(height, ADD_BLOCK_SIZE), \
				NUM_BLOCKS_MAX));
	dim3 grid_size(num_blocks_x, num_blocks_y, 1); 
	dim3 block_size(ADD_BLOCK_SIZE, ADD_BLOCK_SIZE, 1); 

	kMult<<<grid_size, block_size>>>(_data_value, \
			b->getDevData(), target->getDevData(), width, height);
	cudaThreadSynchronize();
}

template <typename Dtype>
void Matrix<Dtype>::eltWiseMult(Matrix<Dtype>* b) {
	eltWiseMult(b, this);
}

template <typename Dtype>
void Matrix<Dtype>::addSum(Matrix<Dtype>* b, Matrix<Dtype>* c, float scaleThis, \
		float scaleB, float scaleC){
	this->add(b, scaleThis, scaleB);	
	this->add(c, 1, scaleC);	
}

template <typename Dtype>
void Matrix<Dtype>::add(Matrix<Dtype>* b, float scaleThis, float scaleB){
	assert(this->isSameDims(b));
	const int width = _shape[1];
	const int height = _shape[0];
	const int num_blocks_x = DIVUP(width, ADD_BLOCK_SIZE);
	assert(num_blocks_x < NUM_BLOCKS_MAX);
	const int num_blocks_y = max(1, min(DIVUP(height, ADD_BLOCK_SIZE), \
				NUM_BLOCKS_MAX));
	dim3 grid_size(num_blocks_x, num_blocks_y, 1); 
	dim3 block_size(ADD_BLOCK_SIZE, ADD_BLOCK_SIZE, 1); 
	
	kAdd<<<grid_size, block_size>>>(this->getDevData(), b->getDevData(), \
			this->getDevData(), scaleThis, scaleB, width, height);
	cudaThreadSynchronize();
}

template <typename Dtype>
void Matrix<Dtype>::showValue(string name){

	Dtype* tmp_yh = new Dtype[_amount];
	this->copyToHost(tmp_yh, _amount);
	cout << "-------------"<< name << "--------------" << endl;
	cout << _shape[0] << ":" << _shape[1] << endl;
	for(int i = 0; i < _shape[0]; i++){
		for(int j = 0; j < _shape[1]; j++){
			cout << tmp_yh[i * _shape[1] + j] << " ";
			if(j != 0 && j % (_shape[1]) == _shape[1]  - 1)
				cout << endl;
			if(_shape[1] == 1)
				cout << endl;
		}
	}
	delete[] tmp_yh;
}

template <typename Dtype>
void Matrix<Dtype>::reValue(Dtype value){
	int length = this->getNumRows() * this->getNumCols();
	for(int i = 0; i < length; i++){
		tmp_yh[i] = value;
	}
	this->copyFromHost(tmp_yh, length);
	delete[] tmp_yh;
}

template <typename Dtype>
void Matrix<Dtype>::reValue(int value){
	int length = this->getNumRows() * this->getNumCols();
	Dtype* tmp_yh = new Dtype[length];
	for(int i = 0; i < length; i++){
		tmp_yh[i] = i % value;
	}
	this->copyFromHost(tmp_yh, length);
	delete[] tmp_yh;
}




















