from argparse import ArgumentParser
import asyncio
import httpx
from itertools import groupby
import logging
import time


parser = ArgumentParser()
parser.add_argument(
    "-e",
    "--endpoint",
    help="The URL of the load balancer including the endpoint to which tests will be sent",
    type=str,
    required=True,
)
parser.add_argument("-b", "--base_trace_id", type=str, default="load-balancer-test")
parser.add_argument("-c", "--request_count", type=int, default=10)
parser.add_argument("-l", "--log_file", type=str, default="./test_load_balancer.log")
args = parser.parse_args()

ENDPOINT = args.endpoint
BASE_TRACE_ID = args.base_trace_id
REQUEST_COUNT = args.request_count
LOG_FILE = args.log_file


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s    [%(levelname)s]    %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger()


def get_aggregate_statistics_by_instance(traces):
    sorted_traces = sorted(traces, key=lambda trace: trace['instance_id'])
    statistics = []
    for instance_id, traces in groupby(sorted_traces, key=lambda trace: trace['instance_id']):
        total_request_time = 0
        count_of_requests = 0
        for trace in traces:
            count_of_requests += 1
            total_request_time += trace["total_request_time"]
        statistics.append({
            "instance_id": instance_id,
            "count_of_requests": count_of_requests,
            "avg_request_time": total_request_time / count_of_requests,
        })
    return statistics


async def make_request(session, url):
    start_time = time.time()
    resp = await session.get(url)
    total_request_time = time.time() - start_time
    trace = resp.json()
    trace["total_request_time"] = total_request_time
    print(trace)
    logger.info(
        f"Request with trace ID \"{trace.get('trace_id')}\" " 
        f"was recieved by instance with ID \"{trace['instance_id']}\" "
        f"and took a total of {total_request_time:.4f} seconds to complete"
    )
    return trace


async def main():
    async with httpx.AsyncClient() as session:
        tasks = []
        for i in range(REQUEST_COUNT):
            url = f"{ENDPOINT}?trace_id={BASE_TRACE_ID}-{i}"
            tasks.append(asyncio.ensure_future(make_request(session, url)))
        traces = await asyncio.gather(*tasks)

        instance_statistics = get_aggregate_statistics_by_instance(traces)
        for s in instance_statistics:
            logger.info(
                f"Instance {s['instance_id']} completed {s['count_of_requests']} requests "
                f"with an average request time of {s['avg_request_time']:.4f} seconds"
            )


if __name__ == "__main__":
    start_time = time.time()
    asyncio.run(main())
    logger.info(
        f"Completed {REQUEST_COUNT} requests in {time.time() - start_time:.4f} seconds"
    )
