//
//  DispatchBenchmark.h
//  Realtime
//
//  Created by Denis Koryttsev on 18/11/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN uint64_t dispatch_benchmark(size_t count, void (^block)(void));
FOUNDATION_EXTERN void dispatch_block_notify(dispatch_block_t block, dispatch_queue_t queue, dispatch_block_t notification_block);

NS_ASSUME_NONNULL_END
