/*
 * Copyright (c) 2009 Mellanox Technologies Ltd. All rights reserved.
 * Copyright (c) 2009 System Fabric Works, Inc. All rights reserved.
 * Copyright (c) 2006-2007 QLogic Corp. All rights reserved.
 * Copyright (c) 2005. PathScale, Inc. All rights reserved.
 *
 * This software is available to you under a choice of one of two
 * licenses.  You may choose to be licensed under the terms of the GNU
 * General Public License (GPL) Version 2, available from the file
 * COPYING in the main directory of this source tree, or the
 * OpenIB.org BSD license below:
 *
 *     Redistribution and use in source and binary forms, with or
 *     without modification, are permitted provided that the following
 *     conditions are met:
 *
 *	- Redistributions of source code must retain the above
 *	  copyright notice, this list of conditions and the following
 *	  disclaimer.
 *
 *	- Redistributions in binary form must reproduce the above
 *	  copyright notice, this list of conditions and the following
 *	  disclaimer in the documentation and/or other materials
 *	  provided with the distribution.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 * BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 * ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#ifndef __BLUERDMA_H__
#define __BLUERDMA_H__

#include <infiniband/driver.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <rdma/bluerdma-abi.h>

#define MAX_WR_IN_SINGLE_POST_REQUEST 1
#define MAX_SG_LIST_LENGTH_FOR_WR 1

struct bluerdma_device {
	struct verbs_device ibv_dev;
	void *driver_data;
	int abi_version;

	// TODO(fh): remove ops, because initialing in `device_alloc` is thread safe
	struct verbs_context_ops *ops;
	void *dl_handle;
	void *(*driver_new)(char *);
	void (*driver_free)(void *);
};

struct bluerdma_context {
	struct verbs_context ibv_ctx;
};

struct bluerdma_cq {
	struct verbs_cq vcq;
};

struct bluerdma_ah {
	struct ibv_ah ibv_ah;
};

struct bluerdma_wq {
	struct bluerdma_queue_buf *queue;
	pthread_spinlock_t lock;
	unsigned int max_sge;
	unsigned int max_inline;
};

struct bluerdma_qp {
	struct verbs_qp vqp;
};

#define to_bxxx(xxx, type)                                                     \
	container_of(ib##xxx, struct bluerdma_##type, ibv_##xxx)

static inline struct bluerdma_context *to_bctx(struct ibv_context *ibctx)
{
	return container_of(ibctx, struct bluerdma_context, ibv_ctx.context);
}

static inline struct bluerdma_device *to_bdev(struct ibv_device *ibdev)
{
	return container_of(ibdev, struct bluerdma_device, ibv_dev.device);
}

static inline struct bluerdma_cq *to_bcq(struct ibv_cq *ibcq)
{
	return container_of(ibcq, struct bluerdma_cq, vcq.cq);
}

static inline struct bluerdma_qp *to_bqp(struct ibv_qp *ibqp)
{
	return container_of(ibqp, struct bluerdma_qp, vqp.qp);
}

static inline struct bluerdma_ah *to_bah(struct ibv_ah *ibah)
{
	return to_bxxx(ah, ah);
}

static inline enum ibv_qp_type qp_type(struct bluerdma_qp *qp)
{
	return qp->vqp.qp.qp_type;
}

#endif /* __BLUERDMA_H__ */
