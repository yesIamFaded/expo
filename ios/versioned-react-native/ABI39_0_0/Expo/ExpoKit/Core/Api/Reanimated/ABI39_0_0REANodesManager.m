#import "ABI39_0_0REANodesManager.h"

#import <ABI39_0_0React/ABI39_0_0RCTConvert.h>

#import "Nodes/ABI39_0_0REANode.h"
#import "Nodes/ABI39_0_0REAPropsNode.h"
#import "Nodes/ABI39_0_0REAStyleNode.h"
#import "Nodes/ABI39_0_0REATransformNode.h"
#import "Nodes/ABI39_0_0REAValueNode.h"
#import "Nodes/ABI39_0_0REABlockNode.h"
#import "Nodes/ABI39_0_0REACondNode.h"
#import "Nodes/ABI39_0_0REAOperatorNode.h"
#import "Nodes/ABI39_0_0REASetNode.h"
#import "Nodes/ABI39_0_0READebugNode.h"
#import "Nodes/ABI39_0_0REAClockNodes.h"
#import "Nodes/ABI39_0_0REAJSCallNode.h"
#import "Nodes/ABI39_0_0REABezierNode.h"
#import "Nodes/ABI39_0_0REAEventNode.h"
#import "ABI39_0_0REAModule.h"
#import "Nodes/ABI39_0_0REAAlwaysNode.h"
#import "Nodes/ABI39_0_0REAConcatNode.h"
#import "Nodes/ABI39_0_0REAParamNode.h"
#import "Nodes/ABI39_0_0REAFunctionNode.h"
#import "Nodes/ABI39_0_0REACallFuncNode.h"

// Interface below has been added in order to use private methods of ABI39_0_0RCTUIManager,
// ABI39_0_0RCTUIManager#UpdateView is a ABI39_0_0React Method which is exported to JS but in 
// Objective-C it stays private
// ABI39_0_0RCTUIManager#setNeedsLayout is a method which updated layout only which
// in its turn will trigger relayout if no batch has been activated

@interface ABI39_0_0RCTUIManager ()

- (void)updateView:(nonnull NSNumber *)ABI39_0_0ReactTag
          viewName:(NSString *)viewName
             props:(NSDictionary *)props;

- (void)setNeedsLayout;

@end


@implementation ABI39_0_0REANodesManager
{
  NSMutableDictionary<ABI39_0_0REANodeID, ABI39_0_0REANode *> *_nodes;
  NSMapTable<NSString *, ABI39_0_0REANode *> *_eventMapping;
  NSMutableArray<id<ABI39_0_0RCTEvent>> *_eventQueue;
  CADisplayLink *_displayLink;
  ABI39_0_0REAUpdateContext *_updateContext;
  BOOL _wantRunUpdates;
  BOOL _processingDirectEvent;
  NSMutableArray<ABI39_0_0REAOnAnimationCallback> *_onAnimationCallbacks;
  NSMutableArray<ABI39_0_0REANativeAnimationOp> *_operationsInBatch;
}

- (instancetype)initWithModule:(ABI39_0_0REAModule *)reanimatedModule
                     uiManager:(ABI39_0_0RCTUIManager *)uiManager
{
  if ((self = [super init])) {
    _reanimatedModule = reanimatedModule;
    _uiManager = uiManager;
    _nodes = [NSMutableDictionary new];
    _eventMapping = [NSMapTable strongToWeakObjectsMapTable];
    _eventQueue = [NSMutableArray new];
    _updateContext = [ABI39_0_0REAUpdateContext new];
    _wantRunUpdates = NO;
    _onAnimationCallbacks = [NSMutableArray new];
    _operationsInBatch = [NSMutableArray new];
  }
  return self;
}

- (void)invalidate
{
  [self stopUpdatingOnAnimationFrame];
}

- (void)operationsBatchDidComplete
{
  if (_displayLink) {
    // if display link is set it means some of the operations that have run as a part of the batch
    // requested updates. We want updates to be run in the same frame as in which operations have
    // been scheduled as it may mean the new view has just been mounted and expects its initial
    // props to be calculated.
    // Unfortunately if the operation has just scheduled animation callback it won't run until the
    // next frame, so it's being triggered manually.
    _wantRunUpdates = YES;
    [self performOperations];
  }
}

- (ABI39_0_0REANode *)findNodeByID:(ABI39_0_0REANodeID)nodeID
{
  return _nodes[nodeID];
}

- (void)postOnAnimation:(ABI39_0_0REAOnAnimationCallback)clb
{
  [_onAnimationCallbacks addObject:clb];
  [self startUpdatingOnAnimationFrame];
}

- (void)postRunUpdatesAfterAnimation
{
  _wantRunUpdates = YES;
  if (!_processingDirectEvent) {
    [self startUpdatingOnAnimationFrame];
  }
}

- (void)startUpdatingOnAnimationFrame
{
  if (!_displayLink) {
    // Setting _currentAnimationTimestamp here is connected with manual triggering of performOperations
    // in operationsBatchDidComplete. If new node has been created and clock has not been started,
    // _displayLink won't be initialized soon enough and _displayLink.timestamp will be 0.
    // However, CADisplayLink is using CACurrentMediaTime so if there's need to perform one more
    // evaluation, it could be used it here. In usual case, CACurrentMediaTime is not being used in
    // favor of setting it with _displayLink.timestamp in onAnimationFrame method.
    _currentAnimationTimestamp = CACurrentMediaTime();
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onAnimationFrame:)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
  }
}

- (void)stopUpdatingOnAnimationFrame
{
  if (_displayLink) {
    [_displayLink invalidate];
    _displayLink = nil;
  }
}

- (void)onAnimationFrame:(CADisplayLink *)displayLink
{
  // We process all enqueued events first
  _currentAnimationTimestamp = _displayLink.timestamp;
  for (NSUInteger i = 0; i < _eventQueue.count; i++) {
    id<ABI39_0_0RCTEvent> event = _eventQueue[i];
    [self processEvent:event];
  }
  [_eventQueue removeAllObjects];

  NSArray<ABI39_0_0REAOnAnimationCallback> *callbacks = _onAnimationCallbacks;
  _onAnimationCallbacks = [NSMutableArray new];

  // When one of the callbacks would postOnAnimation callback we don't want
  // to process it until the next frame. This is why we cpy the array before
  // we iterate over it
  for (ABI39_0_0REAOnAnimationCallback block in callbacks) {
    block(displayLink);
  }

  [self performOperations];

  if (_onAnimationCallbacks.count == 0) {
    [self stopUpdatingOnAnimationFrame];
  }
}

- (void)performOperations
{
  if (_wantRunUpdates) {
    [ABI39_0_0REANode runPropUpdates:_updateContext];
  }
  if (_operationsInBatch.count != 0) {
    NSMutableArray<ABI39_0_0REANativeAnimationOp> *copiedOperationsQueue = _operationsInBatch;
    _operationsInBatch = [NSMutableArray new];
    ABI39_0_0RCTExecuteOnUIManagerQueue(^{
      for (int i = 0; i < copiedOperationsQueue.count; i++) {
        copiedOperationsQueue[i](self.uiManager);
      }
      [self.uiManager setNeedsLayout];
    });
  }
  _wantRunUpdates = NO;
}

- (void)enqueueUpdateViewOnNativeThread:(nonnull NSNumber *)ABI39_0_0ReactTag
                               viewName:(NSString *) viewName
                            nativeProps:(NSMutableDictionary *)nativeProps {
  [_operationsInBatch addObject:^(ABI39_0_0RCTUIManager *uiManager) {
    [uiManager updateView:ABI39_0_0ReactTag viewName:viewName props:nativeProps];
  }];
}

- (void)getValue:(ABI39_0_0REANodeID)nodeID
        callback:(ABI39_0_0RCTResponseSenderBlock)callback
{
  id val = _nodes[nodeID].value;
  if (val) {
    callback(@[val]);
  } else {
    // NULL is not an object and it's not possible to pass it as callback's argument
    callback(@[[NSNull null]]);
  }
}

#pragma mark -- Graph

- (void)createNode:(ABI39_0_0REANodeID)nodeID
            config:(NSDictionary<NSString *, id> *)config
{
  static NSDictionary *map;
  static dispatch_once_t mapToken;
  dispatch_once(&mapToken, ^{
    map = @{@"props": [ABI39_0_0REAPropsNode class],
            @"style": [ABI39_0_0REAStyleNode class],
            @"transform": [ABI39_0_0REATransformNode class],
            @"value": [ABI39_0_0REAValueNode class],
            @"block": [ABI39_0_0REABlockNode class],
            @"cond": [ABI39_0_0REACondNode class],
            @"op": [ABI39_0_0REAOperatorNode class],
            @"set": [ABI39_0_0REASetNode class],
            @"debug": [ABI39_0_0READebugNode class],
            @"clock": [ABI39_0_0REAClockNode class],
            @"clockStart": [ABI39_0_0REAClockStartNode class],
            @"clockStop": [ABI39_0_0REAClockStopNode class],
            @"clockTest": [ABI39_0_0REAClockTestNode class],
            @"call": [ABI39_0_0REAJSCallNode class],
            @"bezier": [ABI39_0_0REABezierNode class],
            @"event": [ABI39_0_0REAEventNode class],
            @"always": [ABI39_0_0REAAlwaysNode class],
            @"concat": [ABI39_0_0REAConcatNode class],
            @"param": [ABI39_0_0REAParamNode class],
            @"func": [ABI39_0_0REAFunctionNode class],
            @"callfunc": [ABI39_0_0REACallFuncNode class],
//            @"listener": nil,
            };
  });

  NSString *nodeType = [ABI39_0_0RCTConvert NSString:config[@"type"]];

  Class nodeClass = map[nodeType];
  if (!nodeClass) {
    ABI39_0_0RCTLogError(@"Animated node type %@ not supported natively", nodeType);
    return;
  }

  ABI39_0_0REANode *node = [[nodeClass alloc] initWithID:nodeID config:config];
  node.nodesManager = self;
  node.updateContext = _updateContext;
  _nodes[nodeID] = node;
}

- (void)dropNode:(ABI39_0_0REANodeID)nodeID
{
  ABI39_0_0REANode *node = _nodes[nodeID];
  if (node) {
    [_nodes removeObjectForKey:nodeID];
  }
}

- (void)connectNodes:(nonnull NSNumber *)parentID childID:(nonnull ABI39_0_0REANodeID)childID
{
  ABI39_0_0RCTAssertParam(parentID);
  ABI39_0_0RCTAssertParam(childID);

  ABI39_0_0REANode *parentNode = _nodes[parentID];
  ABI39_0_0REANode *childNode = _nodes[childID];

  ABI39_0_0RCTAssertParam(childNode);

  [parentNode addChild:childNode];
}

- (void)disconnectNodes:(ABI39_0_0REANodeID)parentID childID:(ABI39_0_0REANodeID)childID
{
  ABI39_0_0RCTAssertParam(parentID);
  ABI39_0_0RCTAssertParam(childID);

  ABI39_0_0REANode *parentNode = _nodes[parentID];
  ABI39_0_0REANode *childNode = _nodes[childID];

  ABI39_0_0RCTAssertParam(childNode);

  [parentNode removeChild:childNode];
}

- (void)connectNodeToView:(ABI39_0_0REANodeID)nodeID
                  viewTag:(NSNumber *)viewTag
                 viewName:(NSString *)viewName
{
  ABI39_0_0RCTAssertParam(nodeID);
  ABI39_0_0REANode *node = _nodes[nodeID];
  ABI39_0_0RCTAssertParam(node);

  if ([node isKindOfClass:[ABI39_0_0REAPropsNode class]]) {
    [(ABI39_0_0REAPropsNode *)node connectToView:viewTag viewName:viewName];
  }
}

- (void)disconnectNodeFromView:(ABI39_0_0REANodeID)nodeID
                       viewTag:(NSNumber *)viewTag
{
  ABI39_0_0RCTAssertParam(nodeID);
  ABI39_0_0REANode *node = _nodes[nodeID];
  ABI39_0_0RCTAssertParam(node);

  if ([node isKindOfClass:[ABI39_0_0REAPropsNode class]]) {
    [(ABI39_0_0REAPropsNode *)node disconnectFromView:viewTag];
  }
}

- (void)attachEvent:(NSNumber *)viewTag
          eventName:(NSString *)eventName
        eventNodeID:(ABI39_0_0REANodeID)eventNodeID
{
  ABI39_0_0RCTAssertParam(eventNodeID);
  ABI39_0_0REANode *eventNode = _nodes[eventNodeID];
  ABI39_0_0RCTAssert([eventNode isKindOfClass:[ABI39_0_0REAEventNode class]], @"Event node is of an invalid type");

  NSString *key = [NSString stringWithFormat:@"%@%@",
                   viewTag,
                   ABI39_0_0RCTNormalizeInputEventName(eventName)];
  ABI39_0_0RCTAssert([_eventMapping objectForKey:key] == nil, @"Event handler already set for the given view and event type");
  [_eventMapping setObject:eventNode forKey:key];
}

- (void)detachEvent:(NSNumber *)viewTag
          eventName:(NSString *)eventName
        eventNodeID:(ABI39_0_0REANodeID)eventNodeID
{
  NSString *key = [NSString stringWithFormat:@"%@%@",
                   viewTag,
                   ABI39_0_0RCTNormalizeInputEventName(eventName)];
  [_eventMapping removeObjectForKey:key];
}

- (void)processEvent:(id<ABI39_0_0RCTEvent>)event
{
  NSString *key = [NSString stringWithFormat:@"%@%@",
                   event.viewTag,
                   ABI39_0_0RCTNormalizeInputEventName(event.eventName)];
  ABI39_0_0REAEventNode *eventNode = [_eventMapping objectForKey:key];
  [eventNode processEvent:event];
}

- (void)processDirectEvent:(id<ABI39_0_0RCTEvent>)event
{
  _processingDirectEvent = YES;
  [self processEvent:event];
  [self performOperations];
  _processingDirectEvent = NO;
}

- (BOOL)isDirectEvent:(id<ABI39_0_0RCTEvent>)event
{
  static NSArray<NSString *> *directEventNames;
  static dispatch_once_t directEventNamesToken;
  dispatch_once(&directEventNamesToken, ^{
    directEventNames = @[
      @"topContentSizeChange",
      @"topMomentumScrollBegin",
      @"topMomentumScrollEnd",
      @"topScroll",
      @"topScrollBeginDrag",
      @"topScrollEndDrag"
    ];
  });
  
  return [directEventNames containsObject:ABI39_0_0RCTNormalizeInputEventName(event.eventName)];
}

- (void)dispatchEvent:(id<ABI39_0_0RCTEvent>)event
{
  NSString *key = [NSString stringWithFormat:@"%@%@",
                   event.viewTag,
                   ABI39_0_0RCTNormalizeInputEventName(event.eventName)];
  ABI39_0_0REANode *eventNode = [_eventMapping objectForKey:key];

  if (eventNode != nil) {
    if ([self isDirectEvent:event]) {
      // Bypass the event queue/animation frames and process scroll events
      // immediately to avoid getting out of sync with the scroll position
      [self processDirectEvent:event];
    } else {
      // enqueue node to be processed
      [_eventQueue addObject:event];
      [self startUpdatingOnAnimationFrame];
    }
  }
}

- (void)configureProps:(NSSet<NSString *> *)nativeProps
               uiProps:(NSSet<NSString *> *)uiProps
{
  _uiProps = uiProps;
  _nativeProps = nativeProps;
}

- (void)setValueForNodeID:(nonnull NSNumber *)nodeID value:(nonnull NSNumber *)newValue
{
  ABI39_0_0RCTAssertParam(nodeID);

  ABI39_0_0REANode *node = _nodes[nodeID];

  ABI39_0_0REAValueNode *valueNode = (ABI39_0_0REAValueNode *)node;
  [valueNode setValue:newValue];
}

@end
