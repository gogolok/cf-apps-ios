import UIKit
import Foundation
import Alamofire
import SwiftyJSON
import Sync
import DATAStack
import ActionSheetPicker_3_0

class AppsViewController: UITableViewController {
    
    @IBOutlet var orgPicker: UIPickerView!
    @IBOutlet var logoutButton: UIBarButtonItem!
    @IBOutlet var orgPickerButton: UIBarButtonItem!
    
    let CellIdentifier = "AppCell"
    
    var dataStack: DATAStack?
    var token:String?
    var items = [CFApp]()
    var currentPage = 1
    var totalPages:Int?
    var orgPickerLabels = [String]()
    var orgPickerValues = [String]()

    required init!(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.refreshControl!.beginRefreshing()
        fetchOrganizations()
    }
    
    func setupPicker() {
        let delegate = OrgPicker()
        self.orgPicker.dataSource = delegate;
        self.orgPicker.delegate = delegate;
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if (segue.identifier == "app") {
            let controller = segue.destinationViewController as! AppViewController
            let cell = sender as! UITableViewCell
            let index = self.tableView.indexPathForCell(cell)
            
            controller.app = items[index!.item]
            controller.dataStack = self.dataStack!
        }
    }
    
    @IBAction func filterOrgClicked(sender: UIBarButtonItem) {
        let currentIndex = self.orgPickerValues.indexOf(CFSession.getOrg()!)
        ActionSheetMultipleStringPicker.showPickerWithTitle("Filter by Org", rows: [
            self.orgPickerLabels
            ], initialSelection: [currentIndex!], doneBlock: {
                picker, values, indexes in
                
                let value = values[0] as! Int
                CFSession.setOrg(self.orgPickerValues[value])
                self.refresh()
                
                return
            }, cancelBlock: { ActionMultipleStringCancelBlock in return }, origin: sender)
    }
    
    func refresh() {
        self.tableView.contentOffset.y -= self.refreshControl!.frame.size.height
        self.refreshControl!.beginRefreshing()
        self.refreshControl!.sendActionsForControlEvents(UIControlEvents.ValueChanged)
    }

    @IBAction func refresh(sender: UIRefreshControl) {
        dispatch_async(dispatch_get_main_queue()) {
            self.currentPage = 1
            self.fetchOrganizations()
        }
    }
    
    func setRefreshTitle(title: String) {
        dispatch_async(dispatch_get_main_queue()) {
            self.refreshControl!.attributedTitle = NSAttributedString(string: title)
        }
    }
    
    func fetchOrganizations() {
        setRefreshTitle("Updating Organizations")
        CFApi().request(CFRequest.Orgs(),
            success: { (json) in
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                    self.handleOrgsResponse(json)
                }
            },
            error: { (statusCode) in
                print([statusCode])
            }
        )
    }
    
    func handleOrgsResponse(json: JSON) {
        do {
            try dataStack!.drop()
        } catch {
            debugPrint("Could not drop database")
        }
        
        self.orgPickerLabels = []
        self.orgPickerValues = []
        var orgGuids: [String] = []
        
        for (key, _) in json["resources"] {
            let index = Int(key)!
            let resource = json["resources"][index]
            
            self.orgPickerValues.append(resource["guid"].stringValue)
            self.orgPickerLabels.append(resource["name"].stringValue)
            orgGuids.append(resource["guid"].stringValue)
        }
        
        self.enableOrgsFilter()
        
        if CFSession.isOrgStale(orgGuids) {
            CFSession.setOrg(orgGuids[0])
        }
        
        let resources = json["resources"].arrayObject as! [[String:AnyObject]]
        CFStore.Orgs(resources, self.dataStack!, { error in
            print("--- Orgs Synced")
            if !CFSession.isEmpty() { self.fetchApplications() }
        }).sync()
    }
    
    func enableOrgsFilter() {
        dispatch_async(dispatch_get_main_queue()) {
            self.orgPickerButton.enabled = true
            self.orgPickerButton.customView?.alpha = 1
        }
    }
    
    func fetchApplications() {
        setRefreshTitle("Updating Apps")
        let urlRequest = CFRequest.Apps(CFSession.getOrg()!, currentPage)
        CFApi().request(urlRequest, success: { (json) in
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                self.handleAppsResponse(json)
            }
            }, error: { (statusCode) in
                print([statusCode])
            }
        )
    }
    
    func fetchCurrentObjects() {
        let request = NSFetchRequest(entityName: "CFApp")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        try! items = dataStack!.mainContext.executeFetchRequest(request) as! [CFApp]
        
        tableView.reloadData()
        
        self.refreshControl!.endRefreshing()
        setRefreshTitle("Refresh Apps")
        self.tableView.tableFooterView = nil
    }
    
    func handleAppsResponse(json: JSON) {
        var appGuids: [String] = []
        
        for (key, _) in json["resources"] {
            let index = Int(key)!
            appGuids.append(json["resources"][index]["guid"].stringValue)
        }
        
        self.totalPages = json["total_pages"].intValue
        
        let resources = json["resources"].arrayObject as! [[String:AnyObject]]
        let clear = currentPage == 1
        CFStore.Apps(resources, self.dataStack!, clear, { error in
            print("--- Apps Synced")
            if !CFSession.isEmpty() { self.fetchSpaces(appGuids) }
        }).sync()
    }
    
    func fetchSpaces(appGuids: [String]) {
        setRefreshTitle("Updating Spaces")
        let urlRequest = CFRequest.Spaces(appGuids)
        CFApi().request(urlRequest, success: { (json) in
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                self.handleSpacesResponse(json)
            }
            }, error: { (statusCode) in
                print([statusCode])
            }
        )
    }

    func handleSpacesResponse(json: JSON) {
        let resources = json["resources"].arrayObject as! [[String:AnyObject]]
        CFStore.Spaces(resources, self.dataStack!, { (error) in
            print("--- Spaces Synced")
            if !CFSession.isEmpty() { self.fetchCurrentObjects() }
        }).sync()
    }
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }
    
    override func tableView(tableView: UITableView, willDisplayCell cell: UITableViewCell, forRowAtIndexPath indexPath: NSIndexPath) {
        if (items.count > 1 && indexPath.row == items.count-1 && currentPage < totalPages) {
            currentPage += 1
            self.tableView.tableFooterView = LoadingIndicatorView()
            fetchApplications()
        }
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = self.tableView.dequeueReusableCellWithIdentifier(CellIdentifier) as! AppTableViewCell
        let app = self.items[indexPath.row]
        cell.render(app, dataStack: self.dataStack!)
        
        return cell
    }
    
    @IBAction func logoutClicked(sender: UIBarButtonItem) {
        CFSession.logout()
    }
}