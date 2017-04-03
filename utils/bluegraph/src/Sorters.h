#ifndef __SORTERS_H__
#define __SORTERS_H__

#include "defines.h"

template <class keyType, class valType>
void bubble_sort_block(void* bufferv, int count );

template <class keyType, class valType>
void quick_sort_block(void* bufferv, int count);

template <class keyType, class valType>
bool check_sorted(void* buffer, int count);
template <class keyType>
bool check_sorted(void* buffer, int count);

template <class keyType, class valType>
int count_from_bytes(int bytes);
template <class keyType>
int count_from_bytes(int bytes);
//template void quick_sort_block<uint32_t,uint32_t>(void*buffer,int count);

#include "Sorters.tpp"

#endif
