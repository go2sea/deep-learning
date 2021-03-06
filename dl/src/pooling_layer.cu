///
/// \file pooling_layer.cu
///

#include "pooling_layer.hpp"

using namespace std;

template <typename Dtype>
PoolingLayer<Dtype>::PoolingLayer(PoolParam *lcp){
	this->_lcp = lcp;
	_num_box = _lcp->getBoxNumHeight()*_lcp->getBoxNumWidth();

	cublasCreate(&this->handle);
	
}

template <typename Dtype>
PoolingLayer<Dtype>::~PoolingLayer() {

	delete this-> _y;
	delete this->_dE_dy;

	if(_lcp->getPoolType() == MAX_POOLING )
		delete _max_pos;
	if((_lcp->getOutHeight() > MAX_THREAD_SIZE \
				|| _lcp->getOutWidth() > MAX_THREAD_SIZE) \
			&& (_lcp->getOverlapHeight() > 0 || _lcp->getOverlapWidth() > 0))
		delete unranged_dE_dx;
	cublasDestroy(this->handle);
}

template <typename Dtype>
void PoolingLayer<Dtype>::initCuda() {


	this->_y               = new Matrix<Dtype>(_lcp->getMinibatchSize(), \
			_lcp->getOutHeight()*_lcp->getOutWidth()* _lcp->getOutChannel());

	this->_dE_dy           = new Matrix<Dtype>(this->_y);


	if(_lcp->getPoolType() == MAX_POOLING ){
		_max_pos           = new Matrix<int>(_lcp->getMinibatchSize(), \
			_lcp->getOutHeight()*_lcp->getOutWidth()* _lcp->getOutChannel());

	}
	if((_lcp->getOutHeight() > MAX_THREAD_SIZE \
				|| _lcp->getOutWidth() > MAX_THREAD_SIZE) \
			&& (_lcp->getOverlapHeight() > 0 || _lcp->getOverlapWidth() > 0)){
		unranged_dE_dx = new Matrix<Dtype>(_lcp->getMinibatchSize(), \
				_lcp->getBoxInHeight()*_lcp->getBoxInWidth() \
				* _lcp->getBoxNumHeight()*_lcp->getBoxNumWidth() \
				* _lcp->getOutChannel());
	}

}

template <typename Dtype>
void PoolingLayer<Dtype>::computeOutput(Matrix<Dtype>* x){

	this->_y->zeros();	

	dim3 blocks = dim3(_lcp->getMinibatchSize(), _lcp->getInChannel() * _num_box);
	dim3 threads = dim3(_lcp->getThreadWidth(), _lcp->getThreadHeight()); 

	if(_lcp->getPoolType() == MAX_POOLING ){
		max_pooling<<<blocks, threads>>>(x->getDevData(), \
				this->_y->getDevData(), _max_pos->getDevData(), \
				_lcp->getInHeight(), _lcp->getInWidth(), \
				_lcp->getInChannel(), \
				_lcp->getOutHeight(), _lcp->getOutWidth(), \
				_lcp->getFilterHeight(), _lcp->getFilterWidth(), \
				_lcp->getStrideHeight(), _lcp->getStrideWidth(), \
				_lcp->getBoxOutHeight(), _lcp->getBoxOutWidth(), \
				_lcp->getBoxNumHeight(), _lcp->getBoxNumWidth());  

	}else if(_lcp->getPoolType() == AVG_POOLING){
		avg_pooling<<<blocks, threads>>>(x->getDevData(), \
				this->_y->getDevData(), \
				_lcp->getInHeight(), _lcp->getInWidth(), \
				_lcp->getInChannel(), \
				_lcp->getOutHeight(), _lcp->getOutWidth(), \
				_lcp->getFilterHeight(), _lcp->getFilterWidth(), \
				_lcp->getStrideHeight(), _lcp->getStrideWidth(), \
				_lcp->getBoxOutHeight(), _lcp->getBoxOutWidth(), \
				_lcp->getBoxNumHeight(), _lcp->getBoxNumWidth());  
	}else{
		cout << "Pooling type is invalid !\n";	
		exit(EXIT_FAILURE);
	}

	cudaThreadSynchronize();
	cudaCheckError();

}

template <typename Dtype>
void PoolingLayer<Dtype>::computeDerivsOfInput(Matrix<Dtype>* dE_dx){

	dim3 blocks = dim3(_lcp->getMinibatchSize(), _lcp->getInChannel() * _num_box);
	dim3 threads = dim3(_lcp->getThreadWidth(), _lcp->getThreadHeight());

	int box_in_height = MAX_THREAD_SIZE > _lcp->getOutHeight() \
				? _lcp->getInHeight() : _lcp->getBoxInHeight();
	int box_in_width = MAX_THREAD_SIZE > _lcp->getOutWidth() \
				? _lcp->getInWidth() : _lcp->getBoxInWidth();

	Dtype* p_dE_dx;
	if((_lcp->getOutHeight() > MAX_THREAD_SIZE \
				|| _lcp->getOutWidth() > MAX_THREAD_SIZE) \
			&& (_lcp->getOverlapHeight() > 0 || _lcp->getOverlapWidth() > 0)){
		unranged_dE_dx->zeros();
		p_dE_dx = unranged_dE_dx->getDevData();
	}else{
		dE_dx->zeros();
		p_dE_dx = dE_dx->getDevData();
	}

	if(_lcp->getPoolType() == MAX_POOLING ){
		compute_dE_dy_max<<<blocks, threads, \
			sizeof(Dtype)*box_in_height*box_in_width>>>( \
					this->_dE_dy->getDevData(), \
					p_dE_dx, _max_pos->getDevData(), \
					box_in_height, box_in_width, \
					_lcp->getBoxOutHeight(), _lcp->getBoxOutWidth(), \
					_lcp->getInChannel(), \
					_lcp->getOutHeight(), _lcp->getOutWidth(), \
					_lcp->getFilterHeight(), _lcp->getFilterWidth(), \
					_lcp->getStrideHeight(), _lcp->getStrideWidth(), \
					_lcp->getBoxNumHeight(), _lcp->getBoxNumWidth());  
		cudaThreadSynchronize();
		cudaCheckError();


	}else if(_lcp->getPoolType() == AVG_POOLING){
		compute_dE_dy_avg<<<blocks, threads, \
			sizeof(Dtype)*box_in_height*box_in_width>>>( \
					this->_dE_dy->getDevData(), p_dE_dx, \
					box_in_height, box_in_width, \
					_lcp->getBoxOutHeight(), _lcp->getBoxOutWidth(), \
					_lcp->getInChannel(), \
					_lcp->getOutHeight(), _lcp->getOutWidth(), \
					_lcp->getFilterHeight(), _lcp->getFilterWidth(), \
					_lcp->getStrideHeight(), _lcp->getStrideWidth(), \
					_lcp->getBoxNumHeight(), _lcp->getBoxNumWidth());  
		cudaThreadSynchronize();
		cudaCheckError();

	}else{
		cout << "Pooling type is invalid !\n";	
		exit(EXIT_FAILURE);
	}

	if((_lcp->getOutHeight() > MAX_THREAD_SIZE \
				|| _lcp->getOutWidth() > MAX_THREAD_SIZE) \
			&& (_lcp->getOverlapHeight() > 0 || _lcp->getOverlapWidth() > 0)){
		dE_dx->zeros();

		compactOverlap<<<_lcp->getMinibatchSize(), _lcp->getInChannel()>>>( \
				unranged_dE_dx->getDevData(), dE_dx->getDevData(), \
				_lcp->getInHeight(), _lcp->getInWidth(), \
				_lcp->getInChannel(),  _lcp->getOverlapHeight(), \
				_lcp->getOverlapWidth(), \
				box_in_height, box_in_width, \
				_lcp->getBoxNumHeight(), _lcp->getBoxNumWidth());  
		cudaThreadSynchronize();
		cudaCheckError();
	}
}



