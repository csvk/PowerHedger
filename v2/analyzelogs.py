import os
import re
import csv
import glob
import sys
from datetime import datetime

class TradeAnalyzerV2:
    def __init__(self, test_dir="test"):
        self.test_dir = test_dir
        self.inputs = {}
        self.deals = []
        self.log_index = {}
        self.report_file = ""
        self.log_file = ""
        
        # State Tracking
        self.sequences = {} # {magic: {state, midPrice, volBuy, volSell, open_positions}}
        self.active_magic = None
        self.last_tally = 0.0
        self.last_unharvested = 0.0
        self.initial_balance = None
        
        self.bal_x = 0.0
        self.bal_y = 0.0
        self.bal_z = 0.0
        
    def find_latest_files(self, provided_log=None):
        reports = glob.glob(os.path.join(self.test_dir, "ReportTester-*.html"))
        if not reports:
            print(f"No HTML report found in {self.test_dir} folder.")
            return False
        self.report_file = max(reports, key=os.path.getmtime)
        
        if provided_log and os.path.exists(provided_log):
            self.log_file = provided_log
        else:
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

    def get_magic_from_comment(self, comment):
        match = re.search(r'\[(\d+)\]', comment)
        if match:
            return int(match.group(1))
        return None

    def analyze(self):
        lot_size = float(self.inputs.get('LotSize', 0))
        contract_size = 100000.0
        output_data = []

        for deal in self.deals:
            time_str = deal['Time']
            comment = deal['Comment']
            deal_price = float(deal['Price'].replace(' ', '')) if deal['Price'] else 0.0
            type_str = deal['Type'].lower()
            direction = deal['Direction'].lower()
            volume = float(deal['Volume'].replace(' ', '')) if deal['Volume'] else 0.0
            order_id = deal['Order']
            deal_profit = float(deal['Profit'].replace(' ', '')) if deal['Profit'] else 0.0
            deal_comm = float(deal['Commission'].replace(' ', '')) if deal['Commission'] else 0.0
            deal_swap = float(deal['Swap'].replace(' ', '')) if deal['Swap'] else 0.0
            deal_balance = float(deal['Balance'].replace(' ', '')) if deal['Balance'] else 0.0
            net_deal_profit = deal_profit + deal_comm + deal_swap
            
            if self.initial_balance is None or deal['Deal'] == '1':
                self.initial_balance = deal_balance
                
            magic = self.get_magic_from_comment(comment)
            related_logs = [self.clean_log(l) for l in self.log_index.get(time_str, [])]
            
            status = "PASS"
            reasoning = "N/A"
            calc_details = ""
            
            for log in related_logs:
                m_state = re.search(r'Tally:\s*([-\d\.]+),\s*Unharvested:\s*([-\d\.]+)', log)
                if m_state:
                    self.last_tally = float(m_state.group(1))
                    self.last_unharvested = float(m_state.group(2))
            
            # --- State Update Logic ---
            inferred_magic = magic
            if inferred_magic is None and type_str in ('buy', 'sell') and direction == 'out':
                # MT5 overwrites comment with 'sl' so magic number is lost. Infer from active trade.
                inferred_magic = self.active_magic
                # If there are multiple open, infer from type matching
                if not inferred_magic:
                    for m, s in self.sequences.items():
                        if s['state'] in ('ACTIVE', 'LOCKED') and ((type_str == 'sell' and s['volBuy'] > 0) or (type_str == 'buy' and s['volSell'] > 0)):
                            inferred_magic = m
                            break

            if inferred_magic is not None:
                if inferred_magic not in self.sequences:
                    self.sequences[inferred_magic] = {
                        'state': 'ACTIVE',
                        'midPrice': 0.0,
                        'volBuy': 0.0,
                        'volSell': 0.0,
                        'open_positions': []
                    }
                
                seq = self.sequences[inferred_magic]
                
                if direction == 'in':
                    if type_str == 'buy':
                        seq['volBuy'] += volume
                    else:
                        seq['volSell'] += volume
                    seq['open_positions'].append({'vol': volume, 'price': deal_price, 'type': type_str, 'order': order_id})
                    
                    # Check related logs for Initial Harvest events
                    for log in related_logs:
                        if "[TRIM] Initial Harvest Triggered" in log:
                            match_h = re.search(r'Harvest \(.*%\): ([\d\.]+)', log)
                            if match_h:
                                h_amt = float(match_h.group(1))
                                seq['harvestedProfit'] = h_amt
                                reasoning = "Initial Harvest Triggered"
                                calc_details = f"Harvested: {h_amt}"
                        if "[TRIM] Symmetrical Trim" in log:
                            match_c = re.search(r'Cost: ([\d\.]+)', log)
                            if match_c:
                                cost = float(match_c.group(1))
                                reasoning = "Symmetrical Trim Cost Checked"
                                calc_details = f"Cost: {cost}"
                    
                    if "[HEDGE]" in comment:
                        seq['state'] = 'LOCKED'
                        # Calculate MidPrice when locked
                        buy_price = (sum(p['price'] * p['vol'] for p in seq['open_positions'] if p['type'] == 'buy') / seq['volBuy']) if seq['volBuy'] > 0 else 0.0
                        sell_price = (sum(p['price'] * p['vol'] for p in seq['open_positions'] if p['type'] == 'sell') / seq['volSell']) if seq['volSell'] > 0 else 0.0
                        seq['midPrice'] = (buy_price + sell_price) / 2.0
                        reasoning = f"Sequence {magic} LOCKED"
                        calc_details = f"MidPrice: {round(seq['midPrice'], 5)}"
                    else:
                        # Signal Entry
                        if self.active_magic and self.active_magic != inferred_magic:
                            # Check if previous active magic is actually gone or still active
                            if self.sequences[self.active_magic]['state'] == 'ACTIVE':
                                status = "FAIL"
                                reasoning = "One-Active-Trade Rule Violation"
                                calc_details = f"New Magic {inferred_magic} entered while {self.active_magic} is still ACTIVE"
                        self.active_magic = inferred_magic
                        reasoning = f"Signal Entry (Magic {inferred_magic})"
                
                elif direction == 'out':
                    # Direction 'out' closes positions
                    remaining = volume
                    # First try to close the specific ticket if logged (though MT5 deals usually represent the closure)
                    # MT5 Deal direction 'out' means closing. Type Buy out = closing Sell. Type Sell out = closing Buy.
                    target_type = 'buy' if type_str == 'sell' else 'sell'
                    
                    i = 0
                    while i < len(seq['open_positions']) and remaining > 0:
                        if seq['open_positions'][i]['type'] == target_type:
                            drop = min(remaining, seq['open_positions'][i]['vol'])
                            seq['open_positions'][i]['vol'] -= drop
                            remaining -= drop
                            if target_type == 'buy': seq['volBuy'] -= drop
                            else: seq['volSell'] -= drop
                            
                            if seq['open_positions'][i]['vol'] <= 0.0001:
                                seq['open_positions'].pop(i)
                            else:
                                i += 1
                        else:
                            i += 1
                    
                    # PRD 5.1: Real-time Profit Recon (Match EA Logic)
                    keep_percent = float(self.inputs.get('HarvestsProfitPercent', 50.0))
                    amount_to_add = 0.0
                    
                    locked_exists = any(s['state'] == 'LOCKED' for s in self.sequences.values())
                    
                    if net_deal_profit > 0:
                        if "[TRIM]" in comment:
                            amount_to_add = net_deal_profit * (keep_percent / 100.0)
                            reasoning = "Symmetrical Trim Win"
                            self.bal_z = deal_balance
                        elif "sl" in comment or "Trailing" in comment:
                            self.bal_x = deal_balance - net_deal_profit
                            self.bal_y = deal_balance
                            
                            reasoning = "Active Trade Exit (SL)"
                            if locked_exists:
                                # Find previously harvested amount
                                prev_harvest = seq.get('harvestedProfit', 0.0)
                                delta = net_deal_profit - prev_harvest
                                if delta > 0:
                                    amount_to_add = delta * (keep_percent / 100.0)
                                    reasoning += f" | +{round(amount_to_add, 2)} Harvest"
                            else:
                                reasoning += " | No Locked, No Harvest"
                    elif net_deal_profit < 0:
                        if "[TRIM]" in comment:
                            reasoning = "Symmetrical Trim Loss"
                            self.bal_z = deal_balance
                    
                    # Removed self.profit_tally increment
                    
                    if seq['volBuy'] <= 0.0001 and seq['volSell'] <= 0.0001:
                        seq['state'] = 'CLOSED'
                        if self.active_magic == inferred_magic:
                            self.active_magic = None
            
            # --- General Rule Checks ---
            if "[SIGNAL]" in comment and direction == 'in':
                if abs(volume - lot_size) > 0.001:
                    status = "FAIL"
                    reasoning = "Lot Size Mismatch"
                    calc_details = f"Expected {lot_size}, got {volume}"

            # --- Result Construction ---
            active_str = str(self.active_magic) if self.active_magic else ""
            
            locked_pairs = []
            for m, s in self.sequences.items():
                if s['state'] == 'LOCKED':
                    vol = max(s['volBuy'], s['volSell'])
                    locked_pairs.append(f"({m},{m}:{vol:.2f})")
            locked_str = ", ".join(locked_pairs)
            locked_count = len(locked_pairs)

            calc_cum_profit = round(deal_balance - self.initial_balance, 2) if self.initial_balance else 0.0
            ea_cum_profit = round(self.last_tally + self.last_unharvested, 2)
            check_diff = round(calc_cum_profit - ea_cum_profit, 2)
            
            bal_check = ""
            if "[TRIM]" in comment and self.bal_x and self.bal_y:
                z_check = "PASS" if self.bal_z > self.bal_x else "FAIL"
                bal_check = f"x={self.bal_x:.2f}, y={self.bal_y:.2f}, z={self.bal_z:.2f} (z>x:{z_check})"

            analysis = {
                'Time': deal['Time'],
                'Symbol': deal['Symbol'],
                'Type': deal['Type'],
                'Direction': deal['Direction'],
                'Volume': deal['Volume'],
                'Price': deal['Price'],
                'Profit': net_deal_profit,
                'Balance': deal['Balance'],
                'Comment': deal['Comment'],
                'ACTIVE': active_str,
                'LOCKED': locked_str,
                'Locked_Count': locked_count,
                'Seq_State': self.sequences[inferred_magic]['state'] if inferred_magic in self.sequences else "N/A",
                'Seq_MidPrice': round(self.sequences[inferred_magic]['midPrice'], 5) if inferred_magic in self.sequences else 0,
                'Tally': self.last_tally,
                'Unharvested': self.last_unharvested,
                'EA_Cum_Profit': ea_cum_profit,
                'Bal_Check': bal_check,
                'Test_Status': status,
                'Reasoning': reasoning
            }
            output_data.append(analysis)

        return output_data

    def save_csv(self, data, filename="v2_trade_analysis.csv"):
        if not data:
            return
        keys = data[0].keys()
        out_path = os.path.join(self.test_dir, filename)
        
        while True:
            try:
                if os.path.exists(out_path):
                    print(f"Deleting existing file: {out_path}")
                    os.remove(out_path)
                with open(out_path, 'w', newline='', encoding='utf-8') as f:
                    dict_writer = csv.DictWriter(f, fieldnames=keys)
                    dict_writer.writeheader()
                    dict_writer.writerows(data)
                print(f"Saved analysis to {out_path}")
                break
            except PermissionError:
                print(f"\n[!] ERROR: Could not save to {out_path}. The file is likely open in another program (e.g., Excel).")
                input("Please close the file and press Enter to retry, or Ctrl+C to cancel...")

        try:
            print(f"Opening {out_path}...")
            os.startfile(out_path)
        except Exception as e:
            print(f"Could not open file: {e}")

if __name__ == "__main__":
    provided_log = sys.argv[1] if len(sys.argv) > 1 else None
    analyzer = TradeAnalyzerV2(test_dir=r"d:\Trading\PowerHedger\test")
    if analyzer.find_latest_files(provided_log):
        if analyzer.parse_html() and analyzer.parse_logs():
            results = analyzer.analyze()
            analyzer.save_csv(results)
