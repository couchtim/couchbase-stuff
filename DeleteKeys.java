
/**
 * Copyright (C) 2009-2012 Couchbase, Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALING IN THE
 * SOFTWARE.
 */
//import java.lang.String;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.util.HashMap;
import java.util.List;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import javax.naming.ConfigurationException;
import net.spy.memcached.*;
import net.spy.memcached.tapmessage.ResponseMessage;

public class DeleteKeys {

  private static MemcachedClient client = null;

  /*
   @Override
   protected void initClient() throws Exception {
   initClient(new BinaryConnectionFactory() {
   @Override
   public long getOperationTimeout() {
   return 15000;
   }

   @Override
   public FailureMode getFailureMode() {
   return FailureMode.Retry;
   }
   });
   }
   */
  public static void fail(String msg) {
    System.err.println("FAILURE: " + msg);
    System.exit(3);
  }

  public static void main(String args[]) throws IOException, InterruptedException, ExecutionException, ConfigurationException {
    List<InetSocketAddress> serverlist = AddrUtil.getAddresses("192.168.1.200:11210");

    client = new MemcachedClient(new BinaryConnectionFactory(), serverlist);

    HashMap<String, Boolean> items = new HashMap<String, Boolean>();
    for (int i = 0; i < 25; i++) {
      client.set("key" + i, 0, "value" + i).get();
      items.put("key" + i + ",value" + i, false);
    }

    client.shutdown(10, TimeUnit.SECONDS);

    // now dump tap
    TapClient tc = new TapClient(serverlist);
    tc.tapDump(null); // may want to consider using named tap

//    long st = System.currentTimeMillis();
    while (tc.hasMoreMessages()) {
//      System.err.println("... Ready to get next message");
      ResponseMessage m;
      if ((m = tc.getNextMessage()) != null) {
        String key = m.getKey() + "," + new String(m.getValue());
        System.out.println("TAPped out a key: " + m.getKey());
        if (!items.containsKey(key)) {
          System.err.println("Received additional item likely left over from"
                  + " previous test: " + m.getKey());
          System.err.println("ResponseMessage : \n" + m);
          continue;
        }
      }
    }
    
    tc.shutdown();
// Flush not supported in couchbase server without enabling it
//      if (!client.flush().get().booleanValue()) {
//        fail("flush() failed");
//      }
  }
}