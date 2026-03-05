import os
import re
import csv
import glob
from datetime import datetime

class TradeAnalyzer:
    def __init__(self, test_dir="test"):
        self.test_dir = test_dir
        self.inputs = {}
        self.deals = []
        self.log_index = {}
        self.report_file = ""
        self.log_file = ""

    def find_latest_files(self):
        reports = glob.glob(os.path.join(self.test_dir, "ReportTester-*.html"))
        if not reports:
            print(f"No HTML report found in {self.test_dir} folder.")
            return False
        self.report_file = max(reports, key=os.path.getmtime)
        
        logs = glob.glob(os.path.join(self.test_dir, "*.log"))
        if not logs:
            print(f"No log file found in {self.test_dir} folder.")
            return False
        self.log_file = max(logs, key=os.path.getmtime)
        
        print(f"Found Report: {self.report_file}")
        print(f"Found Log: {self.log_file}")
        return True

    def parse_html(self):
        if not self.report_file:
            return False
        
        content = ""
        for encoding in ['utf-16', 'utf-8', 'cp1252']:
            try:
                with open(self.report_file, 'r', encoding=encoding) as f:
                    content = f.read()
                if "Strategy Tester Report" in content:
                    print(f"Read HTML with {encoding}")
                    break
            except Exception:
                continue
        
        if not content:
            print("Failed to read HTML report.")
            return False

        input_pattern = re.compile(r'<b>\s*([^=<]+)=([^<]+)</b>')
        matches = input_pattern.findall(content)
        for key, val in matches:
            if key.strip() != "<unnamed>":
                self.inputs[key.strip()] = val.strip()
        
        print(f"Parsed {len(self.inputs)} parameters.")

        header_pos = content.find(">Deals<")
        if header_pos == -1:
            header_pos = content.find("Deals</b>")
            
        if header_pos != -1:
            table_end = content.find("</table>", header_pos)
            deals_html = content[header_pos:table_end]
            
            rows = re.findall(r'<tr.*?>.*?</tr>', deals_html, re.DOTALL)
            for row in rows:
                cols = re.findall(r'<td.*?>(.*?)</td>', row, re.DOTALL)
                if len(cols) >= 12:
                    deal_data = [re.sub(r'<[^>]+>', '', col).strip() for col in cols]
                    if not deal_data: continue
                    
                    if deal_data[1].isdigit():
                        comment = deal_data[12] if len(deal_data) > 12 else ""
                        deal = {
                            'Time': deal_data[0],
                            'Deal': deal_data[1],
                            'Symbol': deal_data[2],
                            'Type': deal_data[3],
                            'Direction': deal_data[4],
                            'Volume': deal_data[5],
                            'Price': deal_data[6],
                            'Order': deal_data[7],
                            'Commission': deal_data[8],
                            'Swap': deal_data[9],
                            'Profit': deal_data[10],
                            'Balance': deal_data[11],
                            'Comment': comment
                        }
                        self.deals.append(deal)
        
        print(f"Parsed {len(self.deals)} deals.")
        return True

    def parse_logs(self):
        if not self.log_file:
            return False
        
        lines = []
        for encoding in ['utf-16', 'utf-8', 'cp1252']:
            try:
                with open(self.log_file, 'r', encoding=encoding) as f:
                    lines = f.readlines()
                if lines:
                    print(f"Read Log with {encoding}")
                    break
            except Exception:
                continue
        
        self.log_index = {}
        time_pattern = re.compile(r'(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2})')
        
        for line in lines:
            match = time_pattern.search(line)
            if match:
                log_time = match.group(1)
                if log_time not in self.log_index:
                    self.log_index[log_time] = []
                self.log_index[log_time].append(line.strip())
        
        print(f"Indexed {len(self.log_index)} unique timestamps in logs.")
        return True

    def clean_log(self, log_line):
        return re.sub(r'^[A-Z]+\s+\d+\s+\d{2}:\d{2}:\d{2}\.\d+\s+[A-Za-z0-9]+\s+\d+\s+\d{4}\.\d{2}\.\d{2}\s+\d{2}:\d{2}:\d{2}\s+', '', log_line)

    def analyze(self):
        hedge_pips = float(self.inputs.get('HedgePips', 0))
        multiplier = float(self.inputs.get('InsidePipMultiplier', 1))
        min_gap = hedge_pips * multiplier
        lot_size = float(self.inputs.get('LotSize', 0))
        
        output_data = []
        open_buy_lots = 0.0
        open_sell_lots = 0.0
        open_positions = [] # List of {vol, price, type, order}
        contract_size = 100000.0
        
        for deal in self.deals:
            time_str = deal['Time']
            deal_id = deal['Deal']
            comment = deal['Comment']
            deal_price = float(deal['Price'].replace(' ', '')) if deal['Price'] else 0.0
            type_str = deal['Type'].lower()
            direction = deal['Direction'].lower()
            volume = float(deal['Volume'].replace(' ', '')) if deal['Volume'] else 0.0
            order_id = deal['Order']
            
            related_logs = [self.clean_log(l) for l in self.log_index.get(time_str, [])]

            # --- Update state FIRST ---
            if direction == 'in':
                if type_str == 'buy':
                    open_buy_lots += volume
                    open_positions.append({'vol': volume, 'price': deal_price, 'type': 'buy', 'order': order_id})
                elif type_str == 'sell':
                    open_sell_lots += volume
                    open_positions.append({'vol': volume, 'price': deal_price, 'type': 'sell', 'order': order_id})
            elif direction == 'out':
                target_ticket = None
                for line in related_logs:
                    match = re.search(r'(?:Ticket|Selected Ticket)\s+(\d+)', line)
                    if match:
                        target_ticket = match.group(1)
                        break
                
                remaining = volume
                if type_str == 'sell': # Sell Out closes Buy
                    open_buy_lots = max(0, open_buy_lots - volume)
                    if target_ticket:
                        for i, pos in enumerate(open_positions):
                            if pos['order'] == target_ticket:
                                drop = min(remaining, pos['vol'])
                                pos['vol'] -= drop
                                remaining -= drop
                                if pos['vol'] <= 0.0001: open_positions.pop(i)
                                break
                    i = 0
                    while i < len(open_positions) and remaining > 0:
                        if open_positions[i]['type'] == 'buy':
                            drop = min(remaining, open_positions[i]['vol'])
                            open_positions[i]['vol'] -= drop
                            remaining -= drop
                        if open_positions[i]['vol'] <= 0.0001:
                            open_positions.pop(i)
                        else:
                            i += 1
                elif type_str == 'buy': # Buy Out closes Sell
                    open_sell_lots = max(0, open_sell_lots - volume)
                    if target_ticket:
                        for i, pos in enumerate(open_positions):
                            if pos['order'] == target_ticket:
                                drop = min(remaining, pos['vol'])
                                pos['vol'] -= drop
                                remaining -= drop
                                if pos['vol'] <= 0.0001: open_positions.pop(i)
                                break
                    i = 0
                    while i < len(open_positions) and remaining > 0:
                        if open_positions[i]['type'] == 'sell':
                            drop = min(remaining, open_positions[i]['vol'])
                            open_positions[i]['vol'] -= drop
                            remaining -= drop
                        if open_positions[i]['vol'] <= 0.0001:
                            open_positions.pop(i)
                        else:
                            i += 1

            # --- Drawdown Calculation AFTER updating state ---
            current_drawdown = 0.0
            pos_breakdown = []
            if deal_price > 0:
                for pos in open_positions:
                    pnl = 0.0
                    if pos['type'] == 'buy':
                        pnl = (deal_price - pos['price']) * pos['vol'] * contract_size
                    else:
                        pnl = (pos['price'] - deal_price) * pos['vol'] * contract_size
                    current_drawdown += pnl
                    pos_breakdown.append(f"#{pos['order']} ({round(pos['vol'], 2)}): {round(pnl, 2)}")
            
            # --- Reasoning & Calculations ---
            reasoning = "N/A"
            calc_details = ""
            status = "PASS"

            if "Hedge" in comment:
                found_log = False
                for line in related_logs:
                    if "Hedge Triggered" in line:
                        reasoning = "Hedge: Barrier Reached"
                        details_match = re.search(r'trigger ([\d.]+).*\(([^:]+): ([\d.]+), HedgePips: ([\d.]+)\)', line)
                        if details_match:
                            calc_details = f"Trigger: {details_match.group(1)}, {details_match.group(2)}: {details_match.group(3)}, Gap Req: {details_match.group(4)}"
                        else:
                            calc_details = line
                        found_log = True
                        break
                if not found_log:
                    reasoning = "Hedge: Portfolio Balancing"
            
            elif any(s in comment for s in ["Random", "Trend", "Reversal"]):
                strategy_name = comment.split(' ')[0]
                found_log = False
                for line in related_logs:
                    if "signal executed" in line.lower():
                        reasoning = f"Strategy: {strategy_name} Entry"
                        calc_details = f"Executed at {deal_price}"
                        found_log = True
                        break
                    elif "signal blocked" in line.lower():
                        reasoning = f"Strategy: {strategy_name} (Warning: Log says blocked)"
                        found_log = True
                
                if not calc_details or "Gap" not in calc_details:
                    for line in related_logs:
                        if "Gap:" in line:
                            match = re.search(r'Gap:\s*([\d.]+).*?MinGap:\s*([\d.]+)', line)
                            if match:
                                gap_val = float(match.group(1))
                                req_gap = float(match.group(2))
                                calc_details = f"Gap: {gap_val}, Min: {req_gap}"
                                if gap_val < req_gap:
                                    status = "FAIL"
                                    reasoning = f"Strategy: {strategy_name} (Rule Breach)"
            
            elif "Trim" in comment:
                reasoning = "Trim: Profit Reduction"
                for line in related_logs:
                    if "Trimming decision" in line or "Trim triggered" in line:
                        match = re.search(r'Ticket (\d+).*?locked ([\d.]+) pips.*?Goal: ([\d.]+)', line)
                        if match:
                            calc_details = f"Target: #{match.group(1)}, Pips: {match.group(2)}, Red. Goal: {match.group(3)}"
                        else:
                            calc_details = line
                        break
            
            elif "sl " in comment:
                reasoning = "Exit: Stop Loss"
                calc_details = f"Closed at {deal_price}"
            
            elif "end of test" in comment:
                reasoning = "Exit: Test Terminated"

            if type_str in ['buy', 'sell'] and direction == 'in':
                if any(s in comment for s in ["Random", "Trend", "Reversal"]):
                    if abs(volume - lot_size) > 0.001:
                        status = "FAIL"
                        reasoning += f" | Vol Error"
                        calc_details += f" (Vol {volume} != Lot {lot_size})"

            # --- Append result ---
            analysis = {
                **deal,
                'Open_Buy_Lots': round(open_buy_lots, 2),
                'Open_Sell_Lots': round(open_sell_lots, 2),
                'Total_Floating_PnL': round(current_drawdown, 2),
                'Position_Breakdown': " | ".join(pos_breakdown),
                'Test Status': status,
                'Resasoning': reasoning,
                'Calculation Details': calc_details
            }
            output_data.append(analysis)

        return output_data

    def save_csv(self, data, filename="test/trade_analysis.csv"):
        if not data:
            return
        keys = data[0].keys()
        os.makedirs(os.path.dirname(filename), exist_ok=True)
        with open(filename, 'w', newline='', encoding='utf-8') as f:
            dict_writer = csv.DictWriter(f, fieldnames=keys)
            dict_writer.writeheader()
            dict_writer.writerows(data)
        print(f"Saved analysis to {filename}")
        
        try:
            print(f"Opening {filename}...")
            os.startfile(os.path.abspath(filename))
        except Exception as e:
            print(f"Could not open file: {e}")

if __name__ == "__main__":
    analyzer = TradeAnalyzer()
    if analyzer.find_latest_files():
        if analyzer.parse_html() and analyzer.parse_logs():
            analysis_results = analyzer.analyze()
            analyzer.save_csv(analysis_results)
